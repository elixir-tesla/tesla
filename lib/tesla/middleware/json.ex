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

  def encodable?(%Tesla.Env{body: body}) when is_binary(body), do: false
  def encodable?(%Tesla.Env{body: nil}), do: false
  def encodable?(env), do: true

  def decode(env, opts) do
    cond do
      env.opts[:stream_response] && decodable_content_type?(env) ->
        decode_stream(env, opts)
      decodable?(env) ->
        Map.update!(env, :body, &process(&1, :decode, opts))
      true ->
        env
    end
  end

  defp decode_stream(env, opts), do: %{env | body: decode_stream_body(env.body, opts)}
  defp decode_stream_body(body, opts) do
    body
    |> Stream.transform('', &decode_stream_transform/2)
    |> Stream.map(&process(&1, :decode, opts))
  end
  defp decode_stream_transform(chunk, acc) do
    {acc, lines} = chunk
      |> :erlang.binary_to_list
      |> Enum.reduce({acc, []}, &decode_stream_reduce/2)
    {Enum.reverse(lines), acc}
  end
  @crlf [?\r, ?\n]
  defp decode_stream_reduce(ch, {'',   lines}) when ch in @crlf, do: {'', lines}
  defp decode_stream_reduce(ch, {head, lines}) when ch in @crlf, do: {'', [to_string(head) | lines]}
  defp decode_stream_reduce(ch, {head, lines}),                  do: {[head, ch], lines}


  def decodable?(env), do: decodable_body?(env) && decodable_content_type?(env)

  def decodable_body?(env) do
    (is_binary(env.body)  && env.body != "") ||
    (is_list(env.body)    && env.body != [])
  end

  def decodable_content_type?(env) do
    case env.headers["Content-Type"] do
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
