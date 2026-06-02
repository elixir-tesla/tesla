defmodule Tesla.Middleware.CompressionTest do
  use ExUnit.Case

  defmodule CompressionGzipRequestClient do
    use Tesla

    plug Tesla.Middleware.Compression, max_body_size: 32 * 1024 * 1024

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

    plug Tesla.Middleware.Compression, format: "deflate", max_body_size: 32 * 1024 * 1024

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

    plug Tesla.Middleware.Compression, max_body_size: 32 * 1024 * 1024

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/response-gzip" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "gzip"}],
             :zlib.gzip("decompressed gzip")}

          "/response-deflate" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "deflate"}],
             :zlib.zip("decompressed deflate")}

          "/single-known-with-unknown" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "zstd, gzip"}],
             :zlib.gzip("decompressed gzip")}

          "/response-identity" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "identity"}], "unchanged"}

          "/response-empty" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "gzip"}], ""}

          "/response-with-content-length" ->
            body = :zlib.gzip("decompressed gzip")

            {200,
             [
               {"content-type", "text/plain"},
               {"content-encoding", "gzip"},
               {"content-length", "#{byte_size(body)}"}
             ], body}

          "/response-empty-with-content-length" ->
            {200,
             [
               {"content-type", "text/plain"},
               {"content-encoding", "gzip"},
               {"content-length", "4194304"}
             ], ""}

          "/stacked-gzip" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "gzip, gzip"}],
             :zlib.gzip(:zlib.gzip("inner"))}

          "/stacked-mixed" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "gzip, deflate"}],
             "irrelevant - never reached"}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "decompress response body (gzip)" do
    assert {:ok, env} = CompressionResponseClient.get("/response-gzip")
    assert env.headers == [{"content-type", "text/plain"}]
    assert env.body == "decompressed gzip"
  end

  test "decompress response body (deflate)" do
    assert {:ok, env} = CompressionResponseClient.get("/response-deflate")
    assert env.body == "decompressed deflate"
  end

  test "stops decompressing on first unsupported content-encoding" do
    assert {:ok, env} = CompressionResponseClient.get("/single-known-with-unknown")
    assert env.body == "decompressed gzip"
    assert env.headers == [{"content-type", "text/plain"}, {"content-encoding", "zstd"}]
  end

  test "return unchanged response for unsupported content-encoding" do
    assert {:ok, env} = CompressionResponseClient.get("/response-identity")
    assert env.body == "unchanged"
    assert env.headers == [{"content-type", "text/plain"}]
  end

  test "raises on invalid empty-body response (gzip)" do
    assert_raise Tesla.Middleware.Compression.Error, fn ->
      CompressionResponseClient.get("/response-empty")
    end
  end

  test "updates existing content-length header" do
    expected_body = "decompressed gzip"
    assert {:ok, env} = CompressionResponseClient.get("/response-with-content-length")
    assert env.body == expected_body

    assert env.headers == [
             {"content-type", "text/plain"},
             {"content-length", "#{byte_size(expected_body)}"}
           ]
  end

  test "preserves compression headers for HEAD requests" do
    assert {:ok, env} = CompressionResponseClient.head("/response-empty-with-content-length")
    assert env.body == ""

    assert env.headers == [
             {"content-type", "text/plain"},
             {"content-encoding", "gzip"},
             {"content-length", "4194304"}
           ]
  end

  test "rejects responses advertising stacked gzip codecs (zip-bomb pattern)" do
    assert_raise Tesla.Middleware.Compression.Error, ~r/more than one supported/, fn ->
      CompressionResponseClient.get("/stacked-gzip")
    end
  end

  test "rejects responses advertising mixed stacked codecs" do
    assert_raise Tesla.Middleware.Compression.Error, ~r/more than one supported/, fn ->
      CompressionResponseClient.get("/stacked-mixed")
    end
  end

  defmodule BombClient do
    use Tesla

    plug Tesla.Middleware.Compression, max_body_size: 1024

    adapter fn env ->
      case env.url do
        "/bomb" ->
          body = :zlib.gzip(:binary.copy(<<0>>, 4 * 1024 * 1024))

          {:ok,
           %{
             env
             | status: 200,
               headers: [
                 {"content-type", "application/octet-stream"},
                 {"content-encoding", "gzip"}
               ],
               body: body
           }}
      end
    end
  end

  test "aborts decompression when output exceeds :max_body_size" do
    assert_raise Tesla.Middleware.Compression.Error, ~r/max_body_size/, fn ->
      BombClient.get("/bomb")
    end
  end

  defmodule MissingLimitClient do
    use Tesla

    plug Tesla.Middleware.Compression

    adapter fn env ->
      {:ok,
       %{
         env
         | status: 200,
           headers: [{"content-type", "text/plain"}, {"content-encoding", "gzip"}],
           body: :zlib.gzip("hello")
       }}
    end
  end

  test "requires :max_body_size to be set" do
    assert_raise ArgumentError, ~r/:max_body_size/, fn ->
      MissingLimitClient.get("/")
    end
  end

  defmodule InfinityLimitClient do
    use Tesla

    plug Tesla.Middleware.Compression, max_body_size: :infinity

    adapter fn env ->
      {:ok,
       %{
         env
         | status: 200,
           headers: [{"content-type", "text/plain"}, {"content-encoding", "gzip"}],
           body: :zlib.gzip("hello")
       }}
    end
  end

  test "accepts :infinity as an explicit opt-out of the cap" do
    assert {:ok, env} = InfinityLimitClient.get("/")
    assert env.body == "hello"
  end

  defmodule CompressRequestDecompressResponseClient do
    use Tesla

    plug Tesla.Middleware.CompressRequest
    plug Tesla.Middleware.DecompressResponse, max_body_size: 32 * 1024 * 1024

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

    plug Tesla.Middleware.Compression, max_body_size: 32 * 1024 * 1024

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "gzip"}],
             TestSupport.gzip_headers(env)}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "Compression headers" do
    assert {:ok, env} = CompressionHeadersClient.get("/")
    assert env.body == "accept-encoding: gzip, deflate, identity"
  end

  defmodule DecompressResponseHeadersClient do
    use Tesla

    plug Tesla.Middleware.DecompressResponse, max_body_size: 32 * 1024 * 1024

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/" ->
            {200, [{"content-type", "text/plain"}, {"content-encoding", "gzip"}],
             TestSupport.gzip_headers(env)}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "Decompress response headers" do
    assert {:ok, env} = DecompressResponseHeadersClient.get("/")
    assert env.body == "accept-encoding: gzip, deflate, identity"
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
