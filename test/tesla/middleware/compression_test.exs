defmodule Tesla.Middleware.CompressionTest do
  use ExUnit.Case

  defmodule CompressionGzipRequestClient do
    use Tesla

    plug Tesla.Middleware.Compression

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/" ->
            {200, [{"content-type", "text/plain"}], :zlib.gunzip(env.body)}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "compress request body (gzip)" do
    assert {:ok, env} = CompressionGzipRequestClient.post("/", "compress request")
    assert env.body == "compress request"
  end

  defmodule CompressionDeflateRequestClient do
    use Tesla

    plug Tesla.Middleware.Compression, format: "deflate"

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/" ->
            {200, [{"content-type", "text/plain"}], :zlib.unzip(env.body)}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "compress request body (deflate)" do
    assert {:ok, env} = CompressionDeflateRequestClient.post("/", "compress request")
    assert env.body == "compress request"
  end

  defmodule CompressionResponseClient do
    use Tesla

    plug Tesla.Middleware.Compression

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/response-gzip" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "gzip"}],
             :zlib.gzip("decompressed gzip")}

          "/response-deflate" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "deflate"}],
             :zlib.zip("decompressed deflate")}

          "/response-identity" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "identity"}], "unchanged"}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "decompress response body (gzip)" do
    assert {:ok, env} = CompressionResponseClient.get("/response-gzip")
    assert env.body == "decompressed gzip"
  end

  test "decompress response body (deflate)" do
    assert {:ok, env} = CompressionResponseClient.get("/response-deflate")
    assert env.body == "decompressed deflate"
  end

  test "return unchanged response for unsupported content-encoding" do
    assert {:ok, env} = CompressionResponseClient.get("/response-identity")
    assert env.body == "unchanged"
  end

  defmodule CompressRequestDecompressResponseClient do
    use Tesla

    plug Tesla.Middleware.CompressRequest
    plug Tesla.Middleware.DecompressResponse

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "gzip"}], env.body}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "CompressRequest / DecompressResponse work without options" do
    alias CompressRequestDecompressResponseClient, as: CRDRClient
    assert {:ok, env} = CRDRClient.post("/", "foo bar")
    assert env.body == "foo bar"
  end

  defmodule CompressionHeadersClient do
    use Tesla

    plug Tesla.Middleware.Compression

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "gzip"}], env.headers}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "Compression headers" do
    assert {:ok, env} = CompressionHeadersClient.get("/")
    assert env.body == [{"accept-encoding", "gzip, deflate"}]
  end

  defmodule DecompressResponseHeadersClient do
    use Tesla

    plug Tesla.Middleware.DecompressResponse

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "gzip"}], env.headers}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "Decompress response headers" do
    assert {:ok, env} = DecompressResponseHeadersClient.get("/")
    assert env.body == [{"accept-encoding", "gzip, deflate"}]
  end

  defmodule CompressRequestHeadersClient do
    use Tesla

    plug Tesla.Middleware.CompressRequest

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "gzip"}], env.headers}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "Compress request headers" do
    assert {:ok, env} = CompressRequestHeadersClient.get("/")
    assert env.body == []
  end
end
