if Code.ensure_loaded?(Msgpax) do
  defmodule Tesla.Middleware.MessagePack do
    @moduledoc """
    Encode requests and decode responses as MessagePack.

    This middleware requires [Msgpax](https://hex.pm/packages/msgpax) as dependency.

    Remember to add `{:msgpax, ">= 2.3.0"}` to dependencies.
    Also, you need to recompile Tesla after adding `:msgpax` dependency:

    ```
    mix deps.clean tesla
    mix deps.compile tesla
    ```

    ## Examples

    ```
    defmodule MyClient do
      use Tesla

      plug Tesla.Middleware.MessagePack
      # or
      plug Tesla.Middleware.MessagePack, engine_opts: [binary: true]
      # or
      plug Tesla.Middleware.MessagePack, decode: &Custom.decode/1, encode: &Custom.encode/1
    end
    ```

    ## Options

    - `:decode` - decoding function
    - `:encode` - encoding function
    - `:encode_content_type` - content-type to be used in request header
    - `:decode_content_types` - list of additional decodable content-types
    - `:engine_opts` - optional engine options
    """

    @behaviour Tesla.Middleware

    @default_decode_content_types ["application/msgpack", "application/x-msgpack"]
    @default_encode_content_type "application/msgpack"

    @impl Tesla.Middleware
    def call(env, next, opts) do
      opts = opts || []

      with {:ok, env} <- encode(env, opts),
           {:ok, env} <- Tesla.run(env, next) do
        decode(env, opts)
      end
    end

    @doc """
    Encode request body as MessagePack.

    It is used by `Tesla.Middleware.EncodeMessagePack`.
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

    defp encode_body(body, opts), do: process(body, :encode, opts)

    defp encode_content_type(opts),
      do: Keyword.get(opts, :encode_content_type, @default_encode_content_type)

    defp encodable?(%{body: nil}), do: false
    defp encodable?(%{body: body}) when is_binary(body), do: false
    defp encodable?(%{body: %Tesla.Multipart{}}), do: false
    defp encodable?(_), do: true

    @doc """
    Decode response body as MessagePack.

    It is used by `Tesla.Middleware.DecodeMessagePack`.
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
      do: @default_decode_content_types ++ Keyword.get(opts, :decode_content_types, [])

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
        opts = Keyword.get(opts, :engine_opts, [])

        case op do
          :encode -> Msgpax.pack(data, opts)
          :decode -> Msgpax.unpack(data, opts)
        end
      end
    end
  end

  defmodule Tesla.Middleware.DecodeMessagePack do
    @moduledoc false
    def call(env, next, opts) do
      opts = opts || []

      with {:ok, env} <- Tesla.run(env, next) do
        Tesla.Middleware.MessagePack.decode(env, opts)
      end
    end
  end

  defmodule Tesla.Middleware.EncodeMessagePack do
    @moduledoc false
    def call(env, next, opts) do
      opts = opts || []

      with {:ok, env} <- Tesla.Middleware.MessagePack.encode(env, opts) do
        Tesla.run(env, next)
      end
    end
  end
end
