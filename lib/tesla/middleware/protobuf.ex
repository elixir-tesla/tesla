defmodule Tesla.Middleware.Protobuf do
  @moduledoc """
  Encode and decode body as Protobuf

  Available options:
  - `:decode` - decoding function
  - `:encode` - encoding function
  - `:engine` - module that implements both encode and decode functions

  **NOTE** It's required to set `:engine` or `:decode` and `:encode`. Otherwise error will
  be raised when it tries to transform data with insufficient configuration.
  """

  @default_content_types ["application/x-protobuf"]

  def call(env, next, opts) do
    opts = opts || []

    env
    |> encode(opts)
    |> Tesla.run(next)
    |> decode(opts)
  end

  def encode(env, opts) do
    cond do
      already_encoded?(env) ->
        env
        |> Tesla.Middleware.Headers.call([], %{"content-type" => "application/x-protobuf"})
      encodable?(env) ->
        env
        |> Map.update!(:body, &encode_body(&1, opts))
        |> Tesla.Middleware.Headers.call([], %{"content-type" => "application/x-protobuf"})
      true ->
        env
    end
  end

  defp encode_body(body, opts), do: process(body, :encode, opts)

  defp already_encoded?(env), do: is_binary(env.body)
  defp encodable?(env),       do: is_map(env.body)

  def decode(env, opts) do
    if decodable?(env) do
      Map.update!(env, :body, &process(&1, :decode, opts))
    else
      env
    end
  end

  def decodable?(env), do: decodable_content_type?(env) && decodable_body?(env)

  def decodable_body?(env) do
    is_binary(env.body) && env.body != ""
  end

  def decodable_content_type?(env) do
    case env.headers["content-type"] do
      nil           -> false
      content_type  -> Enum.any?(@default_content_types, &String.starts_with?(content_type, &1))
    end
  end

  defp process(data, op, opts) do
    cond do
      opts[op] ->
        opts[op].(data)
      opts[:engine] ->
        apply(opts[:engine], op, [data])
      true ->
        raise Tesla.Error, "insufficient protobuf middleware configuration"
    end
  end
end



defmodule Tesla.Middleware.DecodeProtobuf do
  @moduledoc """
  Decode protobuf response body

  Available options:
  - `:decode` - decoding function
  - `:engine` - module that implements decode function

  **NOTE** It's required to set `:engine` or `:decode`. Otherwise error will
  be raised when it tries to transform data with insufficient configuration.
  """

  def call(env, next, opts) do
    opts = opts || []

    env
    |> Tesla.run(next)
    |> Tesla.Middleware.Protobuf.decode(opts)
  end
end

defmodule Tesla.Middleware.EncodeProtobuf do
  @moduledoc """
  Encode request body as Protobuf

  Available options:
  - `:encode` - encoding function
  - `:engine` - module that implements encode function

  **NOTE** It's required to set `:engine` or `:encode`. Otherwise error will
  be raised when it tries to transform data with insufficient configuration.
  """

  def call(env, next, opts) do
    opts = opts || []

    env
    |> Tesla.Middleware.Protobuf.encode(opts)
    |> Tesla.run(next)
  end
end
