defmodule Tesla.Middleware.Compression do
  @moduledoc """
  Compress requests and decompress responses.

  Supports "gzip" and "deflate" encodings using Erlang's built-in `:zlib` module.

  ## Examples

  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.Compression, format: "gzip"
  end
  ```

  ## Options

  - `:format` - request compression format, `"gzip"` (default) or `"deflate"`
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    env
    |> compress(opts)
    |> Tesla.run(next)
    |> decompress()
  end

  defp compressable?(body), do: is_binary(body)

  @doc """
  Compress request.

  It is used by `Tesla.Middleware.CompressRequest`.
  """
  def compress(env, opts) do
    if compressable?(env.body) do
      format = Keyword.get(opts || [], :format, "gzip")

      env
      |> Tesla.put_body(compress_body(env.body, format))
      |> Tesla.put_headers([{"content-encoding", format}])
    else
      env
    end
  end

  defp compress_body(body, "gzip"), do: :zlib.gzip(body)
  defp compress_body(body, "deflate"), do: :zlib.zip(body)

  @doc """
  Decompress response.

  It is used by `Tesla.Middleware.DecompressResponse`.
  """
  def decompress({:ok, env}), do: {:ok, decompress(env)}
  def decompress({:error, reason}), do: {:error, reason}

  def decompress(env) do
    env
    |> Tesla.put_body(decompress_body(env.body, Tesla.get_header(env, "content-encoding")))
  end

  defp decompress_body(<<31, 139, 8, _::binary>> = body, "gzip"), do: :zlib.gunzip(body)
  defp decompress_body(body, "deflate"), do: :zlib.unzip(body)
  defp decompress_body(body, _content_encoding), do: body
end

defmodule Tesla.Middleware.CompressRequest do
  @moduledoc """
  Only compress request.

  See `Tesla.Middleware.Compression` for options.
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    env
    |> Tesla.Middleware.Compression.compress(opts)
    |> Tesla.run(next)
  end
end

defmodule Tesla.Middleware.DecompressResponse do
  @moduledoc """
  Only decompress response.

  See `Tesla.Middleware.Compression` for options.
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, _opts) do
    env
    |> Tesla.run(next)
    |> Tesla.Middleware.Compression.decompress()
  end
end
