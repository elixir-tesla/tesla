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
  Tesla.post(client, "/url", %{key: :value})
  ```

  ## Options

  - `:decode` - decoding function, defaults to `URI.decode_query/1`
  - `:encode` - controls how the body is encoded. Accepts:
    - a function (arity 1) for fully custom encoding
    - `:brackets` — recursive bracket-notation encoder for nested maps
      and lists (see `encode: :brackets` below)
    - `{:brackets, opts}` — same encoder with sub-options. Currently
      supports `boolean_as: :string | :integer` (see `encode: :brackets`
      below).
    - Defaults to `URI.encode_query/1` when omitted.

  ## Nested Maps

  Natively, nested maps are not supported in the body, so
  `%{"foo" => %{"bar" => "baz"}}` won't be encoded and raise an error.
  Support for this specific case is obtained either by setting
  `encode: :brackets` (see `encode: :brackets` below) or by
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
  Tesla.post(client, "/url", %{key: %{nested: "value"}})
  ```

  ## `encode: :brackets`

  Recursive indexed-bracket form encoder for nested maps and lists.

  The output shape — `key[0]=a&key[1]=b` for arrays, `a[b][c]=1` for
  nested objects — is the de-facto convention used by Stripe, Rack,
  PHP's `http_build_query`, qs (with `arrayFormat: 'indices'`), and
  ASP.NET model binding. It is not defined by any RFC. The OpenAPI 3.0.4
  and 3.1.1 specs cover the object case under [`deepObject`
  style](https://spec.openapis.org/oas/v3.1.0#style-values) but
  explicitly state that *"the representation of array or object
  properties is not defined"*, which this encoder fills in with the
  conventions above.

  Percent-encoding of keys and values follows
  `application/x-www-form-urlencoded` (WHATWG URL Standard / PHP's
  default `PHP_QUERY_RFC1738`): spaces become `+`, reserved characters
  become `%XX`.

  ```elixir
  client = Tesla.client([{Tesla.Middleware.FormUrlencoded, encode: :brackets}])

  Tesla.post(client, "/url", %{
    expand: ["objects"],
    objects: %{customers: ["cus_123", "cus_456"]}
  })
  # body: "expand[0]=objects&objects[customers][0]=cus_123&objects[customers][1]=cus_456"
  ```

  ### Booleans (`boolean_as`)

  Booleans default to the lowercase strings `true` / `false`, which is
  the wire format required by Stripe's V2 API (see [stripe-python PR
  #1499](https://github.com/stripe/stripe-python/pull/1499)) and used by
  every official Stripe SDK. PHP's `http_build_query` would instead emit
  `1` for `true` and `0` for `false`; opt in to that behavior with
  `boolean_as: :integer`:

  ```elixir
  # default: Stripe-compatible
  client = Tesla.client([{Tesla.Middleware.FormUrlencoded, encode: :brackets}])
  Tesla.post(client, "/url", %{active: true})
  # body: "active=true"

  # opt in to PHP http_build_query parity
  client =
    Tesla.client([{Tesla.Middleware.FormUrlencoded, encode: {:brackets, boolean_as: :integer}}])
  Tesla.post(client, "/url", %{active: true})
  # body: "active=1"
  ```

  With `boolean_as: :integer`, the encoder's output matches PHP
  `http_build_query` byte-for-byte (after URL-decoding `%5B`/`%5D` to
  literal `[`/`]`) across the verified test corpus. Use `:string`
  (default) for Stripe and most modern APIs; use `:integer` only when
  targeting a server that specifically requires the PHP-native form.

  ### `nil` vs empty string

  The encoder distinguishes "don't include this field" from "include the
  field with an empty value". This matches the three-state semantics
  exposed by Stripe's update endpoints (and PHP's `http_build_query`):

  | Input value | Wire output | Typical API meaning on update |
  | --- | --- | --- |
  | `nil` | (nothing emitted) | Field is absent from the request — the server leaves the existing value untouched. |
  | `""` (empty string) | `key=` | Field is present with an empty value — the server clears or unsets it. |
  | any other value | `key=value` | Field is set to the given value. |

  Use `nil` to mean "leave this field alone" and `""` to mean "clear this
  field". For example, on `POST /v1/customers/cus_X`:

  ```elixir
  # Leaves customer.metadata.foo untouched (field not in request):
  %{metadata: %{plan: "pro"}}
  # → metadata[plan]=pro

  # Deletes the foo key from customer.metadata (sent with empty value):
  %{metadata: %{foo: ""}}
  # → metadata[foo]=
  ```

  Inside lists the same rule applies element-by-element: `nil` elements
  are dropped while the index of remaining elements is preserved
  (`[a, nil, b]` → `[0]=a&[2]=b`, matching PHP `http_build_query`), and
  `""` elements are emitted as `key[i]=`.

  ### Other behavior worth knowing

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

      :brackets ->
        encode_brackets(data)

      {:brackets, sub_opts} when is_list(sub_opts) ->
        validate_brackets_opts!(sub_opts)
        boolean_as = brackets_boolean_as!(sub_opts)

        data
        |> normalize_booleans(boolean_as)
        |> encode_brackets()

      fun when is_function(fun, 1) ->
        fun.(data)

      value ->
        raise ArgumentError,
              "unknown :encode option #{inspect(value)}; expected :brackets, " <>
                "{:brackets, opts} where opts is a keyword list, or an arity-1 function"
    end
  end

  defp brackets_boolean_as!(sub_opts) do
    case Keyword.get(sub_opts, :boolean_as, :string) do
      :string ->
        :string

      :integer ->
        :integer

      other ->
        raise ArgumentError,
              "invalid :boolean_as #{inspect(other)} for :brackets encoder; " <>
                "expected :string or :integer"
    end
  end

  defp validate_brackets_opts!(sub_opts) do
    case Keyword.keys(sub_opts) -- [:boolean_as] do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "unknown option(s) #{inspect(unknown)} for :brackets encoder; " <>
                "expected :boolean_as"
    end
  end

  defp normalize_booleans(data, :string), do: data
  defp normalize_booleans(data, :integer), do: deep_map_booleans(data)

  defp deep_map_booleans(true), do: "1"
  defp deep_map_booleans(false), do: "0"
  defp deep_map_booleans(%_{} = struct), do: struct

  defp deep_map_booleans(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, deep_map_booleans(v)} end)
  end

  defp deep_map_booleans({k, v}), do: {k, deep_map_booleans(v)}
  defp deep_map_booleans(list) when is_list(list), do: Enum.map(list, &deep_map_booleans/1)
  defp deep_map_booleans(other), do: other

  defp do_decode(data, opts) do
    decoder = Keyword.get(opts, :decode, &URI.decode_query/1)
    decoder.(data)
  end

  defp encode_brackets(%module{}) do
    raise ArgumentError,
          "cannot encode #{inspect(module)} struct with :brackets; " <>
            "convert it to a map, string, or other primitive before passing it as the body"
  end

  defp encode_brackets(data) do
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
          "cannot encode #{inspect(module)} struct with :brackets; " <>
            "convert it to a map, string, or other primitive before passing it as the body"
  end

  defp encode_value(value, path) when is_map(value) do
    Enum.flat_map(value, &encode_keyed_entry(&1, path))
  end

  defp encode_value(value, path) when is_list(value) do
    # Keyword.keyword?/1 walks the whole list; accepted because form
    # payloads are small and the alternative (peeking at the head) would
    # misclassify mixed lists like [{:a, 1}, 2].
    if Keyword.keyword?(value) do
      Enum.flat_map(value, &encode_keyed_entry(&1, path))
    else
      # Index first, then drop nils, so original positions are preserved
      # (matches stripe-node: `[a, nil, b]` -> `[0]=a&[2]=b`).
      value
      |> Enum.with_index()
      |> Enum.reject(&indexed_nil?/1)
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

  defp indexed_nil?({nil, _index}), do: true
  defp indexed_nil?({_value, _index}), do: false

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

  defp encode_part(value) when is_tuple(value) do
    raise ArgumentError,
          "cannot encode tuple #{inspect(value)} with :brackets; " <>
            "convert it to a map, string, or other primitive before passing it as the body"
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
