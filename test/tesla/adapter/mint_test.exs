defmodule Tesla.Adapter.MintTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  @internal_error_listener_ref :"mint-internal-error"
  @push_promise_listener_ref :"mint-push-promise"

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Mint
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody

  @large_http2_request_size 70_000

  use Tesla.AdapterCase.SSL,
    transport_opts: [
      cacertfile: Path.join([to_string(:code.priv_dir(:httparrot)), "/ssl/server-ca.crt"])
    ]

  test "timeout request" do
    request = %Env{
      method: :head,
      url: "#{@http}/delay/1"
    }

    assert {:error, :timeout} = call(request, timeout: 100)
  end

  test "max_body option" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/100"
    }

    assert {:error, :body_too_large} = call(request, max_body: 5)
  end

  test "response body as stream" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/1500"
    }

    assert {:ok, %Env{} = response} = call(request, body_as: :stream)
    assert response.status == 200
    assert is_function(response.body)
    assert Enum.join(response.body) |> byte_size() == 2245
  end

  test "response body as chunks with closing body with default" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} = call(request, body_as: :chunks)
    assert response.status == 200
    %{conn: conn, ref: ref, opts: opts, body: body} = response.body
    assert opts[:body_as] == :chunks
    assert opts[:mode] == :passive

    {:ok, conn, received_body} = read_body(conn, ref, opts, body)
    assert byte_size(received_body) == 16

    assert conn.state == :closed
  end

  test "certificates_verification" do
    request = %Env{
      method: :get,
      url: "#{@https}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} =
             call(request,
               certificates_verification: true,
               transport_opts: [
                 verify_fun:
                   {fn
                      _cert, _reason, state ->
                        {:valid, state}
                    end, nil}
               ]
             )

    assert response.status == 200
    assert byte_size(response.body) == 16
  end

  describe "mode: :active" do
    test "body_as: :plain" do
      request = %Env{
        method: :get,
        url: "#{@http}/stream-bytes/10"
      }

      assert {:ok, %Env{} = response} = call(request, mode: :active)
      assert response.status == 200
      assert byte_size(response.body) == 16
    end

    test "body_as: :stream" do
      request = %Env{
        method: :get,
        url: "#{@http}/stream-bytes/10"
      }

      assert {:ok, %Env{} = response} = call(request, body_as: :stream, mode: :active)
      assert response.status == 200
      assert Enum.join(response.body) |> byte_size() == 16
    end

    test "body_as: :chunks" do
      request = %Env{
        method: :get,
        url: "#{@http}/stream-bytes/10"
      }

      assert {:ok, %Env{} = response} = call(request, body_as: :chunks, mode: :active)
      assert response.status == 200
      %{conn: conn, ref: ref, opts: opts, body: body} = response.body

      {:ok, _conn, received_body} = read_body(conn, ref, opts, body)
      assert byte_size(received_body) == 16
    end
  end

  describe "mode: :passive" do
    test "body_as: :plain" do
      request = %Env{
        method: :get,
        url: "#{@http}/stream-bytes/10"
      }

      assert {:ok, %Env{} = response} = call(request, mode: :passive)
      assert response.status == 200
      assert byte_size(response.body) == 16
    end

    test "body_as: :stream" do
      request = %Env{
        method: :get,
        url: "#{@http}/stream-bytes/10"
      }

      assert {:ok, %Env{} = response} = call(request, body_as: :stream, mode: :passive)
      assert response.status == 200
      assert Enum.join(response.body) |> byte_size() == 16
    end

    test "body_as: :chunks" do
      request = %Env{
        method: :get,
        url: "#{@http}/stream-bytes/10"
      }

      assert {:ok, %Env{} = response} = call(request, body_as: :chunks, mode: :passive)
      assert response.status == 200
      %{conn: conn, ref: ref, opts: opts, body: body} = response.body

      {:ok, _conn, received_body} = read_body(conn, ref, opts, body)
      assert byte_size(received_body) == 16
    end
  end

  describe "500 error" do
    test "body_as :plain" do
      request = %Env{
        method: :get,
        url: "#{@http}/status/500"
      }

      assert {:ok, %Env{} = response} = call(request)
      assert response.status == 500
    end

    test "body_as :stream" do
      request = %Env{
        method: :get,
        url: "#{@http}/status/500"
      }

      assert {:ok, %Env{} = response} = call(request, body_as: :stream)
      assert response.status == 500
    end

    test "body_as :chunks" do
      request = %Env{
        method: :get,
        url: "#{@http}/status/500"
      }

      assert {:ok, %Env{} = response} = call(request, body_as: :chunks)
      assert response.status == 500
    end
  end

  describe "reusing active connection" do
    setup do
      uri = URI.parse(@http)
      {:ok, conn} = Mint.HTTP.connect(:http, uri.host, uri.port, mode: :active)
      {:ok, conn: conn, original: "#{uri.host}:#{uri.port}"}
    end

    test "body_as :plain", %{conn: conn, original: original} do
      assert_reused_plain(conn, original, [])
    end

    test "body_as :plain - returns error tuple matching the specification when connection is closed",
         %{conn: conn, original: original} do
      assert_reused_closed_conn_error(conn, original, [])
    end

    test "body_as :stream", %{conn: conn, original: original} do
      assert_reused_stream(conn, original, [])
    end

    test "body_as :chunks", %{conn: conn, original: original} do
      assert_reused_chunks(conn, original, [])
    end

    test "don't reuse connection if original does not match", %{conn: conn} do
      assert_nonmatching_original_opens_new_conn(conn, [])
    end
  end

  describe "reusing passive connection" do
    setup do
      uri = URI.parse(@http)
      {:ok, conn} = Mint.HTTP.connect(:http, uri.host, uri.port, mode: :passive)
      {:ok, conn: conn, original: "#{uri.host}:#{uri.port}"}
    end

    test "body_as :plain", %{conn: conn, original: original} do
      assert_reused_plain(conn, original, mode: :passive)
    end

    test "body_as :plain - returns error tuple matching the specification when connection is closed",
         %{conn: conn, original: original} do
      assert_reused_closed_conn_error(conn, original, mode: :passive)
    end

    test "body_as :stream", %{conn: conn, original: original} do
      assert_reused_stream(conn, original, mode: :passive)
    end

    test "body_as :chunks", %{conn: conn, original: original} do
      assert_reused_chunks(conn, original, mode: :passive)
    end

    test "don't reuse connection if original does not match", %{conn: conn} do
      assert_nonmatching_original_opens_new_conn(conn, mode: :passive)
    end
  end

  describe "issue #394 - handle HTTP/2 request flow control" do
    test "preserves automatic content-length for non-empty HTTP/2 request bodies" do
      body = "hello"

      request = %Env{
        method: :post,
        url: "#{@https}/post",
        headers: [{"content-type", "text/plain"}],
        body: body
      }

      assert {:ok, %Env{} = response} =
               call(request,
                 protocols: [:http2],
                 transport_opts: [cacertfile: httparrot_cacertfile()]
               )

      assert response.status == 200
      assert posted_data(response.body) == body
      assert posted_headers(response.body)["content-length"] == Integer.to_string(byte_size(body))
    end

    test "handles request bodies larger than the flow control window" do
      body = String.duplicate("a", @large_http2_request_size)

      request = %Env{
        method: :post,
        url: "#{@https}/post",
        headers: [{"content-type", "text/plain"}],
        body: body
      }

      assert {:ok, %Env{} = response} =
               call(request,
                 protocols: [:http2],
                 transport_opts: [cacertfile: httparrot_cacertfile()]
               )

      assert response.status == 200
      assert posted_data(response.body) == body
    end

    test "handles streamed request bodies larger than the flow control window" do
      body = large_streamed_http2_body()
      expected = String.duplicate("a", @large_http2_request_size)

      request = %Env{
        method: :post,
        url: "#{@https}/post",
        headers: [{"content-type", "text/plain"}],
        body: body
      }

      assert {:ok, %Env{} = response} =
               call(request,
                 protocols: [:http2],
                 transport_opts: [cacertfile: httparrot_cacertfile()]
               )

      assert response.status == 200
      assert posted_data(response.body) == expected
    end
  end

  describe "issue #394 - handle early HTTP/2 responses during upload" do
    setup do
      listener_ref = :"mint-early-response-#{System.unique_integer([:positive])}"
      dispatch = early_response_dispatch()
      priv_dir = :code.priv_dir(:httparrot)

      {:ok, _pid} =
        :cowboy.start_tls(
          listener_ref,
          [
            port: 0,
            certfile: priv_dir ++ ~c"/ssl/server.crt",
            keyfile: priv_dir ++ ~c"/ssl/server.key"
          ],
          %{env: %{dispatch: dispatch}}
        )

      on_exit(fn -> :cowboy.stop_listener(listener_ref) end)

      {_, port} = :ranch.get_addr(listener_ref)

      {:ok,
       early_response_url: "https://localhost:#{port}",
       early_response_cacertfile: Path.join([to_string(priv_dir), "ssl/server-ca.crt"])}
    end

    test "returns the response body without waiting for another packet", %{
      early_response_url: early_response_url,
      early_response_cacertfile: early_response_cacertfile
    } do
      request = %Env{
        method: :post,
        url: "#{early_response_url}/early-response",
        headers: [{"content-type", "text/plain"}],
        body: String.duplicate("a", @large_http2_request_size)
      }

      assert {:ok, %Env{} = response} =
               call(request,
                 protocols: [:http2],
                 timeout: 200,
                 transport_opts: [cacertfile: early_response_cacertfile]
               )

      assert response.status == 200
      assert response.body == "early response"
    end

    test "returns chunked responses that already finished during upload", %{
      early_response_url: early_response_url,
      early_response_cacertfile: early_response_cacertfile
    } do
      request = %Env{
        method: :post,
        url: "#{early_response_url}/early-response",
        headers: [{"content-type", "text/plain"}],
        body: String.duplicate("a", @large_http2_request_size)
      }

      assert {:ok, %Env{} = response} =
               call(request,
                 body_as: :chunks,
                 protocols: [:http2],
                 timeout: 200,
                 transport_opts: [cacertfile: early_response_cacertfile]
               )

      assert response.status == 200
      assert %{body: {:fin, "early response"}} = response.body
    end

    test "returns streamed responses that already finished during upload", %{
      early_response_url: early_response_url,
      early_response_cacertfile: early_response_cacertfile
    } do
      request = %Env{
        method: :post,
        url: "#{early_response_url}/early-response",
        headers: [{"content-type", "text/plain"}],
        body: String.duplicate("a", @large_http2_request_size)
      }

      assert {:ok, %Env{} = response} =
               call(request,
                 body_as: :stream,
                 protocols: [:http2],
                 timeout: 200,
                 transport_opts: [cacertfile: early_response_cacertfile]
               )

      assert response.status == 200
      assert Enum.join(response.body) == "early response"
    end
  end

  def read_body(conn, _ref, _opts, {:fin, body}), do: {:ok, conn, body}

  def read_body(conn, ref, opts, {:nofin, acc}),
    do: read_body(conn, ref, opts, acc)

  def read_body(conn, ref, opts, acc) do
    case Tesla.Adapter.Mint.read_chunk(conn, ref, opts) do
      {:fin, conn, body} ->
        {:ok, conn, acc <> body}

      {:nofin, conn, part} ->
        read_body(conn, ref, opts, acc <> part)
    end
  end

  defp assert_reused_plain(conn, original, call_opts) do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} = call(request, reused_conn_opts(conn, original, call_opts))
    assert response.status == 200
    assert byte_size(response.body) == 16

    assert {:ok, %Env{} = response} = call(request, reused_conn_opts(conn, original, call_opts))
    assert response.status == 200
    assert byte_size(response.body) == 16

    assert {:ok, conn} = Tesla.Adapter.Mint.close(conn)
    assert conn.state == :closed
  end

  defp assert_reused_closed_conn_error(conn, original, call_opts) do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} = call(request, reused_conn_opts(conn, original, call_opts))
    assert response.status == 200
    assert byte_size(response.body) == 16

    {:ok, conn} = Tesla.Adapter.Mint.close(conn)
    assert conn.state == :closed

    assert {:error, error} = call(request, reused_conn_opts(conn, original, call_opts))

    assert match?(%Mint.HTTPError{reason: :closed, module: Mint.HTTP1}, error) or
             match?(%Mint.TransportError{reason: :einval}, error)
  end

  defp assert_reused_stream(conn, original, call_opts) do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    call_opts = Keyword.put(call_opts, :body_as, :stream)

    assert {:ok, %Env{} = response} = call(request, reused_conn_opts(conn, original, call_opts))
    assert response.status == 200
    assert is_function(response.body)
    assert Enum.join(response.body) |> byte_size() == 16

    assert {:ok, %Env{} = response} = call(request, reused_conn_opts(conn, original, call_opts))
    assert response.status == 200
    assert is_function(response.body)
    assert Enum.join(response.body) |> byte_size() == 16

    assert {:ok, conn} = Tesla.Adapter.Mint.close(conn)
    assert conn.state == :closed
  end

  defp assert_reused_chunks(conn, original, call_opts) do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    call_opts = Keyword.put(call_opts, :body_as, :chunks)

    assert {:ok, %Env{} = response} = call(request, reused_conn_opts(conn, original, call_opts))
    assert response.status == 200
    assert %{conn: received_conn, ref: ref, opts: opts, body: body} = response.body
    {:ok, conn, received_body} = read_body(received_conn, ref, opts, body)
    assert byte_size(received_body) == 16
    assert conn.socket == received_conn.socket

    assert {:ok, %Env{} = response} = call(request, reused_conn_opts(conn, original, call_opts))
    assert response.status == 200
    assert %{conn: received_conn, ref: ref, opts: opts, body: body} = response.body
    {:ok, conn, received_body} = read_body(received_conn, ref, opts, body)
    assert byte_size(received_body) == 16
    assert conn.socket == received_conn.socket

    {:ok, conn} = Tesla.Adapter.Mint.close(conn)
    assert conn.state == :closed
  end

  defp assert_nonmatching_original_opens_new_conn(conn, call_opts) do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    call_opts =
      Keyword.merge([body_as: :chunks, conn: conn, original: "example.com:80"], call_opts)

    assert {:ok, %Env{} = response} = call(request, call_opts)
    assert response.status == 200
    %{conn: received_conn, ref: ref, opts: opts, body: body} = response.body

    {:ok, received_conn, received_body} = read_body(received_conn, ref, opts, body)
    assert byte_size(received_body) == 16
    refute conn.socket == received_conn.socket
    refute opts[:conn]
    assert opts[:old_conn].socket == conn.socket
  end

  defp reused_conn_opts(conn, original, opts) do
    Keyword.merge([conn: conn, original: original, close_conn: false], opts)
  end

  describe "issue #553 - prove real HTTP/2 request resets" do
    setup do
      listener_ref = @internal_error_listener_ref
      dispatch = internal_error_dispatch()
      priv_dir = :code.priv_dir(:httparrot)

      {:ok, _pid} =
        :cowboy.start_tls(
          listener_ref,
          [
            port: 0,
            certfile: priv_dir ++ ~c"/ssl/server.crt",
            keyfile: priv_dir ++ ~c"/ssl/server.key"
          ],
          %{
            env: %{dispatch: dispatch},
            stream_handlers: [Tesla.TestSupport.MintInternalErrorStreamHandler, :cowboy_stream_h]
          }
        )

      on_exit(fn -> :cowboy.stop_listener(listener_ref) end)

      {_, port} = :ranch.get_addr(listener_ref)

      {:ok,
       reset_url: "https://localhost:#{port}",
       reset_cacertfile: Path.join([to_string(priv_dir), "ssl/server-ca.crt"])}
    end

    test "Mint emits server_closed_request from a live HTTP/2 peer", %{
      reset_url: reset_url,
      reset_cacertfile: reset_cacertfile
    } do
      uri = URI.parse(reset_url)

      assert {:ok, conn} =
               Mint.HTTP.connect(:https, uri.host, uri.port,
                 mode: :passive,
                 protocols: [:http2],
                 transport_opts: [cacertfile: reset_cacertfile]
               )

      assert {:ok, conn, ref} = Mint.HTTP.request(conn, "GET", "/stream-reset", [], nil)

      {conn, responses} = recv_until_response(conn, &match?({:error, ^ref, _}, &1))

      assert {:error, ^ref,
              %Mint.HTTPError{
                reason: {:server_closed_request, :internal_error},
                module: Mint.HTTP2
              }} =
               Enum.find(responses, &match?({:error, ^ref, _}, &1))

      assert {:ok, _conn} = Mint.HTTP.close(conn)
    end

    test "Mint emits status and headers before a mid-stream HTTP/2 reset", %{
      reset_url: reset_url,
      reset_cacertfile: reset_cacertfile
    } do
      capture_log(fn ->
        uri = URI.parse(reset_url)

        assert {:ok, conn} =
                 Mint.HTTP.connect(:https, uri.host, uri.port,
                   mode: :passive,
                   protocols: [:http2],
                   transport_opts: [cacertfile: reset_cacertfile]
                 )

        assert {:ok, conn, ref} =
                 Mint.HTTP.request(conn, "GET", "/stream-reset-after-headers", [], nil)

        {conn, responses} = recv_until_response(conn, &match?({:error, ^ref, _}, &1))

        assert {:status, ^ref, 200} = Enum.find(responses, &match?({:status, ^ref, _}, &1))

        assert {:headers, ^ref, _headers} =
                 Enum.find(responses, &match?({:headers, ^ref, _}, &1))

        assert {:error, ^ref,
                %Mint.HTTPError{
                  reason: {:server_closed_request, :internal_error},
                  module: Mint.HTTP2
                }} =
                 Enum.find(responses, &match?({:error, ^ref, _}, &1))

        assert {:ok, _conn} = Mint.HTTP.close(conn)
      end)
    end

    test "Tesla adapter returns the Mint request error instead of crashing", %{
      reset_url: reset_url,
      reset_cacertfile: reset_cacertfile
    } do
      request = %Env{
        method: :get,
        url: "#{reset_url}/stream-reset"
      }

      assert {:error,
              %Mint.HTTPError{
                reason: {:server_closed_request, :internal_error},
                module: Mint.HTTP2
              }} =
               call(request,
                 protocols: [:http2],
                 transport_opts: [cacertfile: reset_cacertfile]
               )
    end

    test "Tesla adapter raises the Mint request error while enumerating stream bodies", %{
      reset_url: reset_url,
      reset_cacertfile: reset_cacertfile
    } do
      capture_log(fn ->
        request = %Env{
          method: :get,
          url: "#{reset_url}/stream-reset-after-headers"
        }

        assert {:ok, %Env{} = response} =
                 call(request,
                   body_as: :stream,
                   protocols: [:http2],
                   transport_opts: [cacertfile: reset_cacertfile]
                 )

        assert response.status == 200

        error =
          assert_raise Mint.HTTPError, fn ->
            Enum.to_list(response.body)
          end

        assert error.reason == {:server_closed_request, :internal_error}
        assert error.module == Mint.HTTP2
      end)
    end
  end

  defp large_streamed_http2_body do
    chunks =
      List.duplicate(String.duplicate("a", 8_192), div(@large_http2_request_size, 8_192))

    chunks =
      case rem(@large_http2_request_size, 8_192) do
        0 -> chunks
        remainder -> chunks ++ [String.duplicate("a", remainder)]
      end

    Stream.map(chunks, & &1)
  end

  defp posted_data(body) do
    body
    |> posted_response()
    |> Map.fetch!("data")
  end

  defp posted_headers(body) do
    body
    |> posted_response()
    |> Map.fetch!("headers")
  end

  defp posted_response(body) do
    Jason.decode!(body)
  end

  defp httparrot_cacertfile do
    Path.join([to_string(:code.priv_dir(:httparrot)), "ssl/server-ca.crt"])
  end

  describe "issue #450 - handle missing Mint response types" do
    setup do
      listener_ref = @push_promise_listener_ref
      dispatch = push_promise_dispatch()
      priv_dir = :code.priv_dir(:httparrot)

      {:ok, _pid} =
        :cowboy.start_tls(
          listener_ref,
          [
            port: 0,
            certfile: priv_dir ++ ~c"/ssl/server.crt",
            keyfile: priv_dir ++ ~c"/ssl/server.key"
          ],
          %{env: %{dispatch: dispatch}}
        )

      on_exit(fn -> :cowboy.stop_listener(listener_ref) end)

      {_, port} = :ranch.get_addr(listener_ref)

      {:ok,
       push_url: "https://localhost:#{port}",
       push_cacertfile: Path.join([to_string(priv_dir), "ssl/server-ca.crt"])}
    end

    test "handles connection errors gracefully" do
      uri = URI.parse(@http)

      request = %Env{
        method: :get,
        url: "http://#{uri.host}:1234"
      }

      assert {:error, _reason} = call(request)
    end

    test "handles malformed requests without crashes" do
      request = %Env{
        method: :get,
        url: "#{@http}/status/500"
      }

      assert {:ok, %Env{} = response} = call(request)
      assert response.status == 500
    end

    test "handles timeout scenarios without crashes" do
      request = %Env{
        method: :get,
        url: "#{@http}/delay/2"
      }

      assert {:error, :timeout} = call(request, timeout: 100)
    end

    test "handles connection drops during streaming" do
      request = %Env{
        method: :get,
        url: "#{@http}/stream-bytes/1000"
      }

      assert {:ok, %Env{} = response} = call(request, body_as: :stream)
      assert response.status == 200

      data = Enum.join(response.body)
      assert byte_size(data) > 0
    end

    test "handles pushed stream responses from a real HTTP/2 server", %{
      push_url: push_url,
      push_cacertfile: push_cacertfile
    } do
      %{host: host, port: port} = URI.parse(push_url)

      assert {:ok, conn} =
               Mint.HTTP.connect(:https, host, port,
                 mode: :passive,
                 transport_opts: [cacertfile: push_cacertfile],
                 protocols: [:http2]
               )

      assert {:ok, conn, ref} = Mint.HTTP.request(conn, "GET", "/index.html", [], nil)

      {conn, responses} =
        recv_until_response(conn, &match?({:push_promise, ^ref, _, _}, &1))

      assert {:push_promise, ^ref, promised_ref, _headers} =
               Enum.find(responses, &match?({:push_promise, ^ref, _, _}, &1))

      {_conn, responses} =
        recv_until_response(conn, &match?({:done, ^promised_ref}, &1), 100, 10, responses)

      assert Enum.any?(responses, &match?({:status, ^promised_ref, 200}, &1))
      assert Enum.any?(responses, &match?({:data, ^promised_ref, _}, &1))
    end

    test "handles push_promise responses from a real HTTP/2 server", %{
      push_url: push_url,
      push_cacertfile: push_cacertfile
    } do
      request = %Env{
        method: :get,
        url: "#{push_url}/index.html"
      }

      assert {:ok, %Env{} = response} =
               call(request,
                 protocols: [:http2],
                 transport_opts: [cacertfile: push_cacertfile]
               )

      assert response.status == 200
      assert response.body == "original response"
    end
  end

  defp push_promise_dispatch do
    :cowboy_router.compile([
      {:_,
       [
         {"/index.html", Tesla.TestSupport.MintPushPromiseIndexHandler, []},
         {"/style.css", Tesla.TestSupport.MintPushPromiseStyleHandler, []}
       ]}
    ])
  end

  defp internal_error_dispatch do
    :cowboy_router.compile([
      {:_,
       [
         {"/stream-reset", Tesla.TestSupport.MintInternalErrorRequestHandler, []},
         {"/stream-reset-after-headers",
          Tesla.TestSupport.MintInternalErrorAfterHeadersRequestHandler, []}
       ]}
    ])
  end

  defp recv_until_response(conn, match?, timeout \\ 100, attempts \\ 10, responses \\ [])

  defp recv_until_response(_conn, _match?, _timeout, 0, responses) do
    flunk("expected Mint to emit a matching response, got: #{inspect(responses)}")
  end

  defp recv_until_response(conn, match?, timeout, attempts, responses) do
    assert {:ok, conn, new_responses} = Mint.HTTP.recv(conn, 0, timeout)

    responses = responses ++ new_responses

    if Enum.any?(responses, match?) do
      {conn, responses}
    else
      recv_until_response(conn, match?, timeout, attempts - 1, responses)
    end
  end

  defp early_response_dispatch do
    :cowboy_router.compile([
      {:_, [{"/early-response", Tesla.TestSupport.MintEarlyResponseHandler, []}]}
    ])
  end
end
