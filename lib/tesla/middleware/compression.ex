defmodule Tesla.Middleware.Compression do
  @behaviour Tesla.Middleware

  @moduledoc """
  Compress requests and decompress responses.

  Supports "gzip" and "deflate" encodings using erlang's built-in `:zlib` module.

  ### Example usage
  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.Compression, format: "gzip"
  end
  ```

  ### Options
  - `:format` - request compression format, `"gzip"` (default) or `"deflate"`
  """

  def call(env, next, opts) do
    env
    |> compress(opts)
    |> Tesla.run(next)
    |> decompress()
  end

  defp compressable?(body), do: is_binary(body)

  @doc """
  Compress request, used by `Tesla.Middleware.CompressRequest`
  """
  def compress(env, opts) do
    if compressable?(env.body) do
      format = Keyword.get(opts || [], :format, "gzip")

      env
      |> Map.update!(:body, &compress_body(&1, format))
      |> Tesla.Middleware.Headers.call([], %{"Content-Encoding" => format})
    else
      env
    end
  end

  defp compress_body(body, "gzip"), do: :zlib.gzip(body)
  defp compress_body(body, "deflate"), do: :zlib.zip(body)

  @doc """
  Decompress response, used by `Tesla.Middleware.DecompressResponse`
  """
  def decompress(env) do
    env
    |> Map.update!(:body, &decompress_body(&1, env.headers["content-encoding"]))
  end

  defp decompress_body(<<31, 139, 8, _::binary>> = body, "gzip"), do: :zlib.gunzip(body)
  defp decompress_body(body, "deflate"), do: :zlib.unzip(body)
  defp decompress_body(body, _content_encoding), do: body
end

defmodule Tesla.Middleware.CompressRequest do
  @behaviour Tesla.Middleware

  @moduledoc """
  Only compress request.

  See `Tesla.Middleware.Compression` for options.
  """

  def call(env, next, opts) do
    env
    |> Tesla.Middleware.Compression.compress(opts)
    |> Tesla.run(next)
  end
end

defmodule Tesla.Middleware.DecompressResponse do
  @behaviour Tesla.Middleware

  @moduledoc """
  Only decompress response.

  See `Tesla.Middleware.Compression` for options.
  """

  def call(env, next, _opts) do
    env
    |> Tesla.run(next)
    |> Tesla.Middleware.Compression.decompress()
  end
end
