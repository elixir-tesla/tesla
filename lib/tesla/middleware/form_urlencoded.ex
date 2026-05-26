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

  ## Serialization Styles

  The `:encode` option supports built-in serialization styles that mirror
  OpenAPI's Encoding Object `style` field. OpenAPI defines four values:
  `form` (default), `spaceDelimited`, `pipeDelimited`, and `deepObject`.
  The middleware currently implements `:deep_object`; the other styles
  may be added later.

  ### `encode: :deep_object`

  Recursive bracket-notation encoder for bodies that contain maps,
  structs, or lists. The flat default behavior is unchanged when `:encode`
  is not set.

  Output shape:

  - Nested maps and structs: `parent[child]=value`.
  - Lists: `parent[0]=a&parent[1]=b` (numeric indices).
  - Lists of objects: `items[0][name]=a&items[1][name]=b`.

  OpenAPI defines `deepObject` for object values only and leaves array
  serialization unspecified; this middleware extends the style to arrays
  using numeric bracket indices, the convention used by Stripe, PHP's
  `http_build_query`, and many code-generated SDKs. Bracket characters in
  keys are emitted literally; only the segments between them are
  percent-encoded.

  ```elixir
  defmodule MyClient do
    def client do
      Tesla.client([
        {Tesla.Middleware.FormUrlencoded, encode: :deep_object}
      ])
    end
  end

  body = %{
    expand: ["objects"],
    objects: %{customers: ["cus_123", "cus_456"], charges: nil},
    validation_behavior: :fix
  }

  MyClient.post(client, "/url", body)
  # =>
  # expand[0]=objects
  # &objects[customers][0]=cus_123
  # &objects[customers][1]=cus_456
  # &validation_behavior=fix
  ```

  Encoding behavior:

  - Nested maps recurse.
  - Nested structs that implement `String.Chars` (e.g. `DateTime`, `Date`,
    `URI`, `Decimal`) are encoded via `to_string/1`. Structs without a
    `String.Chars` implementation fall back to `Map.from_struct/1` and
    recurse like maps. A top-level struct is always unwrapped with
    `Map.from_struct/1`.
  - Keyword lists are encoded as nested objects (`parent[key]=value`),
    not as numerically indexed arrays.
  - `nil` is dropped at every level, including inside lists (indices are
    assigned after filtering).
  - Booleans encode as `"true"` / `"false"`.
  - Atoms encode via `Atom.to_string/1`; everything else via `to_string/1`.
  - Keys and values are escaped with `URI.encode_www_form/1`.
  - Output ordering follows Elixir map traversal order and is not
    guaranteed across runs; treat the encoded string as a multiset of
    pairs, not an ordered sequence.

  Decoding remains flat regardless of `:encode`. If you need to decode
  nested form responses, configure `:decode` with `&Plug.Conn.Query.decode/1`.
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

  defp encode_deep_object(data) when is_struct(data),
    do: encode_deep_object(Map.from_struct(data))

  defp encode_deep_object(data) do
    data
    |> Enum.flat_map(&encode_root_entry/1)
    |> Enum.join("&")
  end

  defp encode_root_entry({key, value}), do: encode_value(value, [key])

  defp encode_value(nil, _path), do: []

  defp encode_value(value, path) when is_struct(value) do
    if String.Chars.impl_for(value) do
      encode_value(to_string(value), path)
    else
      encode_value(Map.from_struct(value), path)
    end
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

  defp encode_keyed_entry({key, value}, path), do: encode_value(value, [key | path])

  defp encode_indexed_entry({value, index}, path), do: encode_value(value, [index | path])

  defp encode_path(path) do
    [root | rest] = Enum.reverse(path)

    Enum.reduce(rest, encode_part(root), &append_bracket/2)
  end

  defp append_bracket(part, encoded), do: "#{encoded}[#{encode_part(part)}]"

  defp encode_part(value) when is_atom(value),
    do: value |> Atom.to_string() |> URI.encode_www_form()

  defp encode_part(value), do: value |> to_string() |> URI.encode_www_form()
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
