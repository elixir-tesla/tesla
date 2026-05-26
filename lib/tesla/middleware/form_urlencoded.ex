defmodule Tesla.Middleware.FormUrlencoded do
  @moduledoc """
  Send request body as `application/x-www-form-urlencoded`.

  Performs encoding of `body` from a `Map` such as `%{"foo" => "bar"}` into
  URL-encoded data.

  Performs decoding of the response into a map when urlencoded and content-type
  is `application/x-www-form-urlencoded`, so `"foo=bar"` becomes
  `%{"foo" => "bar"}`.

  ## Examples

  ```elixir
  defmodule Myclient do
    def client do
      Tesla.client([
        {Tesla.Middleware.FormUrlencoded,
          encode: &Plug.Conn.Query.encode/1,
          decode: &Plug.Conn.Query.decode/1}
      ])
    end
  end

  client = Myclient.client()
  Myclient.post(client, "/url", %{key: :value})
  ```

  ## Options

  - `:decode` - decoding function, defaults to `URI.decode_query/1`
  - `:encode` - controls how the body is encoded. Accepts:
    - a function (arity 1) for fully custom encoding
    - `:deep_object` — recursive bracket-notation encoder based on
      OpenAPI's `deepObject` style (see *Serialization Styles* below)
    - Defaults to `URI.encode_query/1` when omitted.

  ## Nested Maps

  Natively, nested maps are not supported in the body, so
  `%{"foo" => %{"bar" => "baz"}}` won't be encoded and raise an error.
  Support for this specific case is obtained either by setting
  `encode: :deep_object` (see *Serialization Styles* below) or by
  configuring the middleware to encode (and decode) with
  `Plug.Conn.Query`:

  ```elixir
  defmodule Myclient do
    def client do
      Tesla.client([
        {Tesla.Middleware.FormUrlencoded,
          encode: &Plug.Conn.Query.encode/1,
          decode: &Plug.Conn.Query.decode/1}
      ])
    end
  end

  client = Myclient.client()
  Myclient.post(client, "/url", %{key: %{nested: "value"}})
  ```

  ## `encode: :deep_object`

  Recursive bracket-notation encoder for nested maps and lists, modeled
  on OpenAPI's `deepObject` style and extended to arrays with numeric
  indices (the convention used by Stripe, `http_build_query`, and most
  code-generated SDKs).

  ```elixir
  Tesla.client([{Tesla.Middleware.FormUrlencoded, encode: :deep_object}])
  |> Tesla.post("/url", %{
    expand: ["objects"],
    objects: %{customers: ["cus_123", "cus_456"]}
  })
  # body: "expand[0]=objects&objects[customers][0]=cus_123&objects[customers][1]=cus_456"
  ```

  Behavior worth knowing:

  - `nil` is dropped at every level; list indices are assigned after filtering.
  - Keyword lists encode as objects (`parent[key]=value`), not arrays.
  - Structs raise `ArgumentError` — convert them with `Map.from_struct/1`
    or `to_string/1` first.
  - Output order is not guaranteed (maps don't preserve insertion order).
  - Decoding stays flat; pair with `decode: &Plug.Conn.Query.decode/1` for
    symmetric round-trips.
  """

  @behaviour Tesla.Middleware

  @content_type "application/x-www-form-urlencoded"

  @impl Tesla.Middleware
  def call(env, next, opts) do
    env
    |> encode(opts)
    |> Tesla.run(next)
    |> case do
      {:ok, env} -> {:ok, decode(env, opts)}
      error -> error
    end
  end

  @doc """
  Encode response body as querystring.

  It is used by `Tesla.Middleware.EncodeFormUrlencoded`.
  """
  def encode(env, opts) do
    if encodable?(env) do
      env
      |> Map.update!(:body, &encode_body(&1, opts))
      |> Tesla.put_headers([{"content-type", @content_type}])
    else
      env
    end
  end

  defp encodable?(%{body: nil}), do: false
  defp encodable?(%{body: %Tesla.Multipart{}}), do: false
  defp encodable?(_), do: true

  defp encode_body(body, _opts) when is_binary(body), do: body
  defp encode_body(body, opts), do: do_encode(body, opts)

  @doc """
  Decode response body as querystring.

  It is used by `Tesla.Middleware.DecodeFormUrlencoded`.
  """
  def decode(env, opts) do
    if decodable?(env) do
      env
      |> Map.update!(:body, &decode_body(&1, opts))
    else
      env
    end
  end

  defp decodable?(env), do: decodable_body?(env) && decodable_content_type?(env)

  defp decodable_body?(env) do
    (is_binary(env.body) && env.body != "") || (is_list(env.body) && env.body != [])
  end

  defp decodable_content_type?(env) do
    case Tesla.get_header(env, "content-type") do
      nil -> false
      content_type -> String.starts_with?(content_type, @content_type)
    end
  end

  defp decode_body(body, opts), do: do_decode(body, opts)

  defp do_encode(data, opts) do
    case Keyword.get(opts, :encode) do
      nil ->
        URI.encode_query(data)

      :deep_object ->
        encode_deep_object(data)

      fun when is_function(fun, 1) ->
        fun.(data)

      value ->
        raise ArgumentError,
              "unknown :encode option #{inspect(value)}; expected :deep_object or an arity-1 function"
    end
  end

  defp do_decode(data, opts) do
    decoder = Keyword.get(opts, :decode, &URI.decode_query/1)
    decoder.(data)
  end

  defp encode_deep_object(%module{}) do
    raise ArgumentError,
          "cannot encode #{inspect(module)} struct with :deep_object; " <>
            "convert it to a map, string, or other primitive before passing it as the body"
  end

  defp encode_deep_object(data) do
    data
    |> Enum.flat_map(&encode_root_entry/1)
    |> Enum.join("&")
  end

  defp encode_root_entry({key, value}) do
    encode_value(value, [key])
  end

  defp encode_value(nil, _path) do
    []
  end

  defp encode_value(%module{}, _path) do
    raise ArgumentError,
          "cannot encode #{inspect(module)} struct with :deep_object; " <>
            "convert it to a map, string, or other primitive before passing it as the body"
  end

  defp encode_value(value, path) when is_map(value) do
    Enum.flat_map(value, &encode_keyed_entry(&1, path))
  end

  defp encode_value(value, path) when is_list(value) do
    if Keyword.keyword?(value) do
      Enum.flat_map(value, &encode_keyed_entry(&1, path))
    else
      value
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index()
      |> Enum.flat_map(&encode_indexed_entry(&1, path))
    end
  end

  defp encode_value(value, path) do
    ["#{encode_path(path)}=#{encode_part(value)}"]
  end

  defp encode_keyed_entry({key, value}, path) do
    encode_value(value, [key | path])
  end

  defp encode_indexed_entry({value, index}, path) do
    encode_value(value, [index | path])
  end

  defp encode_path(path) do
    [root | rest] = Enum.reverse(path)

    Enum.reduce(rest, encode_part(root), &append_bracket/2)
  end

  defp append_bracket(part, encoded) do
    "#{encoded}[#{encode_part(part)}]"
  end

  defp encode_part(value) when is_atom(value) do
    value |> Atom.to_string() |> URI.encode_www_form()
  end

  defp encode_part(value) do
    value |> to_string() |> URI.encode_www_form()
  end
end

defmodule Tesla.Middleware.DecodeFormUrlencoded do
  @behaviour Tesla.Middleware

  @impl true
  def call(env, next, opts) do
    opts = opts || []

    with {:ok, env} <- Tesla.run(env, next) do
      {:ok, Tesla.Middleware.FormUrlencoded.decode(env, opts)}
    end
  end
end

defmodule Tesla.Middleware.EncodeFormUrlencoded do
  @behaviour Tesla.Middleware

  @impl true
  def call(env, next, opts) do
    opts = opts || []

    with env <- Tesla.Middleware.FormUrlencoded.encode(env, opts) do
      Tesla.run(env, next)
    end
  end
end
