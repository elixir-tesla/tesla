defmodule Tesla.Middleware.Compression do
  def call(env, next, opts) do
    env
    |> compress(opts)
    |> Tesla.run(next)
    |> decompress()
  end

  def compressable?(body), do: is_binary(body)

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

  def compress_body(body, "gzip"),    do: :zlib.gzip(body)
  def compress_body(body, "deflate"), do: :zlib.zip(body)

  def decompress(env) do
    env
    |> Map.update!(:body, &decompress_body(&1, env.headers["content-encoding"]))
  end

  def decompress_body(<<31, 139, 8, _ :: binary>> = body, "gzip"), do: :zlib.gunzip(body)
  def decompress_body(body, "deflate"),                            do: :zlib.unzip(body)
  def decompress_body(body, _content_encoding),                    do: body
end

defmodule Tesla.Middleware.CompressRequest do
  def call(env, next, opts) do
    env
    |> Tesla.Middleware.Compression.compress(opts)
    |> Tesla.run(next)
  end
end

defmodule Tesla.Middleware.DecompressResponse do
  def call(env, next, _opts) do
    env
    |> Tesla.run(next)
    |> Tesla.Middleware.Compression.decompress()
  end
end
