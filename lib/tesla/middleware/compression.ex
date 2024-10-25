defmodule Tesla.Middleware.Compression do
  @moduledoc """
  Compress requests and decompress responses.

  Supports "gzip" and "deflate" encodings using Erlang's built-in `:zlib` module.

  ## Examples

  ```elixir
  defmodule MyClient do
    def client do
      Tesla.client([
        {Tesla.Middleware.Compression, format: "gzip"}
      ])
    end
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
    |> add_accept_encoding()
    |> Tesla.run(next)
    |> decompress()
  end

  @doc false
  def add_accept_encoding(env) do
    Tesla.put_headers(env, [{"accept-encoding", "gzip, deflate, identity"}])
  end

  defp compressible?(body), do: is_binary(body)

  @doc """
  Compress request.

  It is used by `Tesla.Middleware.CompressRequest`.
  """
  def compress(env, opts) do
    if compressible?(env.body) do
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
    codecs = compression_algorithms(Tesla.get_header(env, "content-encoding"))
    {decompressed_body, unknown_codecs} = decompress_body(codecs, env.body, [])

    env
    |> put_decompressed_body(decompressed_body)
    |> put_or_delete_content_encoding(unknown_codecs)
  end

  defp put_or_delete_content_encoding(env, []) do
    Tesla.delete_header(env, "content-encoding")
  end

  defp put_or_delete_content_encoding(env, unknown_codecs) do
    Tesla.put_header(env, "content-encoding", Enum.join(unknown_codecs, ", "))
  end

  defp decompress_body([gzip | rest], body, acc) when gzip in ["gzip", "x-gzip"] do
    decompress_body(rest, :zlib.gunzip(body), acc)
  end

  defp decompress_body(["deflate" | rest], body, acc) do
    decompress_body(rest, :zlib.unzip(body), acc)
  end

  defp decompress_body(["identity" | rest], body, acc) do
    decompress_body(rest, body, acc)
  end

  defp decompress_body([codec | rest], body, acc) do
    decompress_body(rest, body, [codec | acc])
  end

  defp decompress_body([], body, acc) do
    {body, acc}
  end

  defp compression_algorithms(nil) do
    []
  end

  defp compression_algorithms(value) do
    value
    |> String.downcase()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reverse()
  end

  defp put_decompressed_body(env, body) do
    env
    |> Tesla.put_body(body)
    |> Tesla.delete_header("content-length")
  end
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
    |> Tesla.Middleware.Compression.add_accept_encoding()
    |> Tesla.run(next)
    |> Tesla.Middleware.Compression.decompress()
  end
end
