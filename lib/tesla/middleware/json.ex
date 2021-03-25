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

  ## Examples

  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.JSON # use jason engine
    # or
    plug Tesla.Middleware.JSON, engine: JSX, engine_opts: [strict: [:comments]]
    # or
    plug Tesla.Middleware.JSON, engine: Poison, engine_opts: [keys: :atoms]
    # or
    plug Tesla.Middleware.JSON, decode: &JSX.decode/1, encode: &JSX.encode/1
  end
  ```

  ## Options

  - `:decode` - decoding function
  - `:encode` - encoding function
  - `:encode_content_type` - content-type to be used in request header
  - `:engine` - encode/decode engine, e.g `Jason`, `Poison` or `JSX`  (defaults to Jason)
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
  def decode(env, opts) do
    with true <- decodable?(env, opts),
         {:ok, body} <- decode_body(env.body, opts) do
      {:ok, %{env | body: body}}
    else
      false -> {:ok, env}
      error -> error
    end
  end

  defp decode_body(body, opts), do: process(body, :decode, opts)

  defp decodable?(env, opts), do: decodable_body?(env) && decodable_content_type?(env, opts)

  defp decodable_body?(env) do
    (is_binary(env.body) && env.body != "") || (is_list(env.body) && env.body != [])
  end

  defp decodable_content_type?(env, opts) do
    case Tesla.get_header(env, "content-type") do
      nil -> false
      content_type -> Enum.any?(content_types(opts), &String.starts_with?(content_type, &1))
    end
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
      engine = Keyword.get(opts, :engine, @default_engine)
      opts = Keyword.get(opts, :engine_opts, [])

      apply(engine, op, [data, opts])
    end
  end
end

defmodule Tesla.Middleware.DecodeJson do
  @moduledoc false
  def call(env, next, opts) do
    opts = opts || []

    with {:ok, env} <- Tesla.run(env, next) do
      Tesla.Middleware.JSON.decode(env, opts)
    end
  end
end

defmodule Tesla.Middleware.EncodeJson do
  @moduledoc false
  def call(env, next, opts) do
    opts = opts || []

    with {:ok, env} <- Tesla.Middleware.JSON.encode(env, opts) do
      Tesla.run(env, next)
    end
  end
end
