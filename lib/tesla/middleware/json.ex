defmodule Tesla.Middleware.JSON do
  @moduledoc """
  Encode requests and decode responses as JSON.

  This middleware requires [Jason](https://hex.pm/packages/jason) (or other engine) as dependency.

  Remember to add `{:jason, ">= 1.0"}` to dependencies.
  Also, you need to recompile Tesla after adding `:jason` dependency:

  ```
  mix deps.clean tesla
  mix deps.compile tesla
  ```

  > #### Using built-in `JSON` from Elixir 1.18 {: .info}
  >
  > This middleware supports the built-in `JSON` module introduced in ELixir 1.18, but for historical
  > reasons is it not the default. To use it, set it as the `:engine`:
  >
  >     {Tesla.Middleware.JSON, engine: JSON}
  >
  > For more advanced usage using custom encoders/decodes, provide the `:encode` and `:decode` anonymous functions instead.

  If you only need to encode the request body or decode the response body,
  you can use `Tesla.Middleware.EncodeJson` or `Tesla.Middleware.DecodeJson` directly instead.

  ## Examples

  ```
  defmodule MyClient do
    def client do
      Tesla.client([
        # use jason engine
        Tesla.Middleware.JSON,
        # or
        {Tesla.Middleware.JSON, engine: JSON}
        # or
        {Tesla.Middleware.JSON, engine: JSX, engine_opts: [strict: [:comments]]},
        # or
        {Tesla.Middleware.JSON, engine: Poison, engine_opts: [keys: :atoms]},
        # or
        {Tesla.Middleware.JSON, decode: &JSX.decode/1, encode: &JSX.encode/1}
      ])
    end
  end
  ```

  ## Options

  - `:decode` - decoding function
  - `:encode` - encoding function
  - `:encode_content_type` - content-type to be used in request header
  - `:engine` - encode/decode engine, e.g `JSON`, `Jason`, `Poison` or `JSX`  (defaults to Jason)
  - `:engine_opts` - optional engine options
  - `:decode_content_types` - list of additional decodable content-types
  """

  @behaviour Tesla.Middleware

  # NOTE: text/javascript added to support Facebook Graph API.
  #       see https://github.com/teamon/tesla/pull/13
  @default_content_types ["application/json", "text/javascript"]
  @default_encode_content_type "application/json"
  @default_engine Jason

  @impl Tesla.Middleware
  def call(env, next, opts) do
    opts = opts || []

    with {:ok, env} <- encode(env, opts),
         {:ok, env} <- Tesla.run(env, next) do
      decode(env, opts)
    end
  end

  @doc """
  Encode request body as JSON.

  It is used by `Tesla.Middleware.EncodeJson`.
  """
  @spec encode(Tesla.Env.t(), keyword()) :: Tesla.Env.result()
  def encode(env, opts) do
    with true <- encodable?(env),
         {:ok, body} <- encode_body(env.body, opts) do
      {:ok,
       env
       |> Tesla.put_body(body)
       |> Tesla.put_headers([{"content-type", encode_content_type(opts)}])}
    else
      false -> {:ok, env}
      error -> error
    end
  end

  defp encode_body(%Stream{} = body, opts), do: {:ok, encode_stream(body, opts)}
  defp encode_body(body, opts) when is_function(body), do: {:ok, encode_stream(body, opts)}
  defp encode_body(body, opts), do: process(body, :encode, opts)

  defp encode_content_type(opts),
    do: Keyword.get(opts, :encode_content_type, @default_encode_content_type)

  defp encode_stream(body, opts) do
    Stream.map(body, fn item ->
      {:ok, body} = encode_body(item, opts)
      body <> "\n"
    end)
  end

  defp encodable?(%{body: nil}), do: false
  defp encodable?(%{body: body}) when is_binary(body), do: false
  defp encodable?(%{body: %Tesla.Multipart{}}), do: false
  defp encodable?(_), do: true

  @doc """
  Decode response body as JSON.

  It is used by `Tesla.Middleware.DecodeJson`.
  """
  @spec decode(Tesla.Env.t(), keyword()) :: Tesla.Env.result()
  def decode(env, opts) do
    with true <- decodable?(env, opts),
         {:ok, body} <- decode_body(env.body, opts) do
      {:ok, %{env | body: body}}
    else
      false -> {:ok, env}
      error -> error
    end
  end

  defp decode_body(body, opts) when is_struct(body, Stream) or is_function(body),
    do: {:ok, decode_stream(body, opts)}

  defp decode_body(body, opts), do: process(body, :decode, opts)

  defp decodable?(env, opts), do: decodable_body?(env) && decodable_content_type?(env, opts)

  defp decodable_body?(env) do
    (is_binary(env.body) && env.body != "") ||
      (is_list(env.body) && env.body != []) ||
      is_function(env.body) ||
      is_struct(env.body, Stream)
  end

  defp decodable_content_type?(env, opts) do
    case Tesla.get_header(env, "content-type") do
      nil ->
        false

      content_type ->
        content_type = String.downcase(content_type)

        opts
        |> content_types()
        |> Enum.any?(&String.starts_with?(content_type, &1))
    end
  end

  defp decode_stream(body, opts) do
    Stream.map(body, fn chunk ->
      case decode_body(chunk, opts) do
        {:ok, item} -> item
        _ -> chunk
      end
    end)
  end

  defp content_types(opts),
    do: @default_content_types ++ Keyword.get(opts, :decode_content_types, [])

  defp process(data, op, opts) do
    case do_process(data, op, opts) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, {__MODULE__, op, reason}}
      {:error, reason, _pos} -> {:error, {__MODULE__, op, reason}}
    end
  rescue
    ex in Protocol.UndefinedError ->
      {:error, {__MODULE__, op, ex}}
  end

  defp do_process(data, op, opts) do
    # :encode/:decode
    if fun = opts[op] do
      fun.(data)
    else
      engine =
        case Keyword.fetch(opts, :engine) do
          # Special case for JSON, which doesn't have encode/2 nor return {:ok, json}
          {:ok, JSON} -> Tesla.Middleware.JSON.JSONAdapter
          {:ok, engine} -> engine
          :error -> @default_engine
        end

      opts = Keyword.get(opts, :engine_opts, [])

      apply(engine, op, [data, opts])
    end
  end
end

defmodule Tesla.Middleware.DecodeJson do
  @moduledoc """
  Decodes response body as JSON.

  Only decodes the body if the `Content-Type` header suggests
  that the body is JSON.
  """
  @moduledoc since: "1.8.0"

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    opts = opts || []

    with {:ok, env} <- Tesla.run(env, next) do
      Tesla.Middleware.JSON.decode(env, opts)
    end
  end
end

defmodule Tesla.Middleware.EncodeJson do
  @moduledoc """
  Encodes request body as JSON.
  """
  @moduledoc since: "1.8.0"

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    opts = opts || []

    with {:ok, env} <- Tesla.Middleware.JSON.encode(env, opts) do
      Tesla.run(env, next)
    end
  end
end
