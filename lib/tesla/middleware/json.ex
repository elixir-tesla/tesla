defmodule Tesla.Middleware.JSON do
  # NOTE: text/javascript added to support Facebook Graph API.
  #       see https://github.com/teamon/tesla/pull/13
  @content_types ["application/json", "text/javascript"]
  @default_engine Poison

  @doc """
  Encode and decode response body as JSON

  Available options:
  - `:decode` - decoding function
  - `:encode` - encoding function
  - `:engine` - encode/decode engine, e.g `Poison` or `JSX`  (defaults to Poison)
  - `:engine_opts` - optional engine options
  """
  def call(env, next, opts) do
    opts = opts || []

    env
    |> encode(opts)
    |> Tesla.run(next)
    |> decode(opts)
  end

  def encode(env, opts) do
    if encodable?(env) do
      env
      |> Map.update!(:body, &encode_body(&1, opts))
      |> Tesla.Middleware.Headers.call([], %{"content-type" => "application/json"})
    else
      env
    end
  end

  defp encode_body(%Stream{} = body, opts),             do: encode_stream(body, opts)
  defp encode_body(body, opts) when is_function(body),  do: encode_stream(body, opts)
  defp encode_body(body, opts), do: process(body, :encode, opts)

  defp encode_stream(body, opts) do
    Stream.map body, fn item -> encode_body(item, opts) <> "\n" end
  end

  def encodable?(env), do: env.body != nil

  def decode(env, opts) do
    if decodable?(env) do
      Map.update!(env, :body, &process(&1, :decode, opts))
    else
      env
    end
  end

  def decodable?(env), do: decodable_body?(env) && decodable_content_type?(env)
  def decodable_body?(env), do: is_binary(env.body) || is_list(env.body)
  def decodable_content_type?(env) do
    case env.headers["content-type"] do
      nil           -> false
      content_type  -> Enum.any?(@content_types, &String.starts_with?(content_type, &1))
    end
  end

  defp process(data, op, opts) do
    with {:ok, value} <- do_process(data, op, opts) do
      value
    else
      {:error, reason} -> raise %Tesla.Error{message: "JSON #{op} error: #{inspect reason}", reason: reason}
    end
  end

  defp do_process(data, op, opts) do
    if fun = opts[op] do # :encode/:decode
      fun.(data)
    else
      engine  = Keyword.get(opts, :engine, @default_engine)
      opts    = Keyword.get(opts, :engine_opts, [])

      apply(engine, op, [data, opts])
    end
  end
end



defmodule Tesla.Middleware.DecodeJson do
  def call(env, next, opts \\ []) do
    env
    |> Tesla.run(next)
    |> Tesla.Middleware.JSON.decode(opts)
  end
end

defmodule Tesla.Middleware.EncodeJson do
  def call(env, next, opts \\ []) do
    env
    |> Tesla.Middleware.JSON.encode(opts)
    |> Tesla.run(next)
  end
end
