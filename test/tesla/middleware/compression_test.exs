defmodule CompressionTest do
  use ExUnit.Case

  use Tesla.MiddlewareCase, middleware: Tesla.Middleware.Compression
  use Tesla.MiddlewareCase, middleware: Tesla.Middleware.CompressRequest
  use Tesla.MiddlewareCase, middleware: Tesla.Middleware.DecompressResponse


  defmodule CompressionGzipRequestClient do
    use Tesla

    plug Tesla.Middleware.Compression

    adapter fn (env) ->
      {status, headers, body} = case env.url do
        "/" ->
          {200, %{'Content-Type' => 'text/plain'}, :zlib.gunzip(env.body)}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "compress request body (gzip)" do
    assert CompressionGzipRequestClient.post("/", "compress request").body == "compress request"
  end

  defmodule CompressionDeflateRequestClient do
    use Tesla

    plug Tesla.Middleware.Compression, format: "deflate"

    adapter fn (env) ->
      {status, headers, body} = case env.url do
        "/" ->
          {200, %{'Content-Type' => 'text/plain'}, :zlib.unzip(env.body)}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "compress request body (deflate)" do
    assert CompressionDeflateRequestClient.post("/", "compress request").body == "compress request"
  end

  defmodule CompressionResponseClient do
    use Tesla

    plug Tesla.Middleware.Compression

    adapter fn (env) ->
      {status, headers, body} = case env.url do
        "/response-gzip" ->
          {200, %{'Content-Type' => 'text/plain', 'Content-Encoding' => 'gzip'}, :zlib.gzip("decompressed gzip")}
        "/response-deflate" ->
          {200, %{'Content-Type' => 'text/plain', 'Content-Encoding' => 'deflate'}, :zlib.zip("decompressed deflate")}
        "/response-identity" ->
          {200, %{'Content-Type' => 'text/plain', 'Content-Encoding' => 'identity'}, "unchanged"}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "decompress response body (gzip)" do
    assert CompressionResponseClient.get("/response-gzip").body == "decompressed gzip"
  end

  test "decompress response body (deflate)" do
    assert CompressionResponseClient.get("/response-deflate").body == "decompressed deflate"
  end

  test "return unchanged response for unsupported content-encoding" do
    assert CompressionResponseClient.get("/response-identity").body == "unchanged"
  end

  defmodule CompressRequestDecompressResponseClient do
    use Tesla

    plug Tesla.Middleware.CompressRequest
    plug Tesla.Middleware.DecompressResponse

    adapter fn (env) ->
      {status, headers, body} = case env.url do
        "/" ->
          {200, %{'Content-Type' => 'text/plain', 'Content-Encoding' => 'gzip'}, env.body}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "CompressRequest / DecompressResponse work without options" do
    alias CompressRequestDecompressResponseClient, as: CRDRClient
    assert CRDRClient.post("/", "foo bar").body == "foo bar"
  end
end
