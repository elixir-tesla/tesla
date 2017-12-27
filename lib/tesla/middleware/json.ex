defmodule Tesla.Middleware.JSON do
  @behaviour Tesla.Middleware

  @moduledoc """
  Encode requests and decode responses as JSON.

  This middleware requires [poison](https://hex.pm/packages/poison) (or other engine) as dependency.

  Remember to add `{:poison, ">= 1.0"}` to dependencies (and `:poison` to applications in `mix.exs`)
  Also, you need to recompile tesla after adding `:poison` dependency:

  ```
  mix deps.clean tesla
  mix deps.compile tesla
  ```


  ### Example usage
  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.JSON # use poison engine
    # or
    plug Tesla.Middleware.JSON, engine: JSX, engine_opts: [strict: [:comments]]
    # or
    plug Tesla.Middleware.JSON, decode: &JSX.decode/1, encode: &JSX.encode/1
  end
  ```

  ### Options
  - `:decode` - decoding function
  - `:encode` - encoding function
  - `:engine` - encode/decode engine, e.g `Poison` or `JSX`  (defaults to Poison)
  - `:engine_opts` - optional engine options
  - `:decode_content_types` - list of additional decodable content-types
  """

  # NOTE: text/javascript added to support Facebook Graph API.
  #       see https://github.com/teamon/tesla/pull/13
  @default_content_types ["application/json", "text/javascript"]
  @default_engine Poison

  def call(env, next, opts) do
    opts = opts || []

    env
    |> encode(opts)
    |> Tesla.run(next)
    |> decode(opts)
  end

  @doc """
  Encode request body as JSON. Used by `Tesla.Middleware.EncodeJson`
  """
  def encode(env, opts) do
    if encodable?(env) do
      env
      |> Map.update!(:body, &encode_body(&1, opts))
      |> Tesla.Middleware.Headers.call([], %{"content-type" => "application/json"})
    else
      env
    end
  end

  defp encode_body(%Stream{} = body, opts), do: encode_stream(body, opts)
  defp encode_body(body, opts) when is_function(body), do: encode_stream(body, opts)
  defp encode_body(body, opts), do: process(body, :encode, opts)

  defp encode_stream(body, opts) do
    Stream.map(body, fn item -> encode_body(item, opts) <> "\n" end)
  end

  defp encodable?(%{body: nil}), do: false
  defp encodable?(%{body: body}) when is_binary(body), do: false
  defp encodable?(%{body: %Tesla.Multipart{}}), do: false
  defp encodable?(_), do: true

  @doc """
  Decode response body as JSON. Used by `Tesla.Middleware.DecodeJson`
  """
  def decode(env, opts) do
    if decodable?(env, opts) do
      Map.update!(env, :body, &process(&1, :decode, opts))
    else
      env
    end
  end

  defp decodable?(env, opts), do: decodable_body?(env) && decodable_content_type?(env, opts)

  defp decodable_body?(env) do
    (is_binary(env.body) && env.body != "") || (is_list(env.body) && env.body != [])
  end

  defp decodable_content_type?(env, opts) do
    case env.headers["content-type"] do
      nil -> false
      content_type -> Enum.any?(content_types(opts), &String.starts_with?(content_type, &1))
    end
  end

  defp content_types(opts),
    do: @default_content_types ++ Keyword.get(opts, :decode_content_types, [])

  defp process(data, op, opts) do
    with {:ok, value} <- do_process(data, op, opts) do
      value
    else
      {:error, reason} ->
        raise %Tesla.Error{message: "JSON #{op} error: #{inspect(reason)}", reason: reason}

      {:error, msg, position} ->
        reason = {msg, position}
        raise %Tesla.Error{message: "JSON #{op} error: #{inspect(reason)}", reason: reason}
    end
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
  def call(env, next, opts) do
    opts = opts || []

    env
    |> Tesla.run(next)
    |> Tesla.Middleware.JSON.decode(opts)
  end
end

defmodule Tesla.Middleware.EncodeJson do
  def call(env, next, opts) do
    opts = opts || []

    env
    |> Tesla.Middleware.JSON.encode(opts)
    |> Tesla.run(next)
  end
end
