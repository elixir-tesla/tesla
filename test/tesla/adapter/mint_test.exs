defmodule Tesla.Adapter.MintTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  @internal_error_listener_ref :"mint-internal-error"
  @push_promise_listener_ref :"mint-push-promise"

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Mint
  use Tesla.AdapterCase.Basic, empty_response_body: nil
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.Query

  @large_http2_request_size 70_000
  @default_connection_window_size 65_535
  @wide_stream_window_size 1_048_576

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

  test "response body as stream is empty when the response has no body" do
    request = %Env{
      method: :get,
      url: "#{@http}/status/204"
    }

    assert {:ok, %Env{} = response} = call(request, body_as: :stream)
    assert response.status == 204
    assert Enum.to_list(response.body) == []
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

  test "unsupported scheme does not mint atoms" do
    request = %Env{
      method: :get,
      url: "atk-#{:erlang.unique_integer([:positive])}://127.0.0.1/"
    }

    before_count = :erlang.system_info(:atom_count)
    assert {:error, :unsupported_scheme} = call(request)
    after_count = :erlang.system_info(:atom_count)

    assert after_count == before_count
  end

  test "streamed request that Mint rejects returns a two-tuple error" do
    request = %Env{
      method: :post,
      url: "#{@http}/post",
      headers: [{"bad header", "value"}],
      body: Stream.map(["a"], & &1)
    }

    before_ports = owned_port_count()

    for _ <- 1..20 do
      assert {:error, %Mint.HTTPError{reason: {:invalid_header_name, "bad header"}}} =
               call(request, protocols: [:http1])
    end

    assert owned_port_count() == before_ports
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

    test "keeps the content-length the request already carries" do
      body = "hello"

      request = %Env{
        method: :post,
        url: "#{@https}/post",
        headers: [
          {"content-type", "text/plain"},
          {"content-length", Integer.to_string(byte_size(body))}
        ],
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

    for size <- [65_535, 65_536, 1_000_000] do
      @flow_control_size size

      test "uploads #{size} bytes across the HTTP/2 flow control window" do
        body = String.duplicate("a", @flow_control_size)

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
        assert byte_size(posted_data(response.body)) == @flow_control_size
      end
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

  describe "issue #394 - handle HTTP/2 connection window exhaustion" do
    setup do
      listener_ref = :"mint-connection-window-#{System.unique_integer([:positive])}"
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
            env: %{dispatch: upload_echo_dispatch()},
            initial_stream_window_size: @wide_stream_window_size,
            max_stream_window_size: @wide_stream_window_size,
            max_connection_window_size: @default_connection_window_size
          }
        )

      on_exit(fn -> :cowboy.stop_listener(listener_ref) end)

      {_, port} = :ranch.get_addr(listener_ref)

      {:ok,
       upload_url: "https://localhost:#{port}",
       upload_cacertfile: Path.join([to_string(priv_dir), "ssl/server-ca.crt"])}
    end

    test "uploads a body that exhausts the connection window before the stream window", %{
      upload_url: upload_url,
      upload_cacertfile: upload_cacertfile
    } do
      body_length = @default_connection_window_size * 3

      request = %Env{
        method: :post,
        url: "#{upload_url}/upload",
        headers: [{"content-type", "text/plain"}],
        body: String.duplicate("a", body_length)
      }

      assert {:ok, %Env{} = response} =
               call(request,
                 protocols: [:http2],
                 transport_opts: [cacertfile: upload_cacertfile]
               )

      assert response.status == 200
      assert response.body == Integer.to_string(body_length)
    end

    test "uploads a streamed body that exhausts the connection window", %{
      upload_url: upload_url,
      upload_cacertfile: upload_cacertfile
    } do
      body_length = @default_connection_window_size * 3
      chunk = String.duplicate("a", 8_192)
      chunk_count = div(body_length, 8_192)

      request = %Env{
        method: :post,
        url: "#{upload_url}/upload",
        headers: [{"content-type", "text/plain"}],
        body: Stream.map(1..chunk_count, fn _ -> chunk end)
      }

      assert {:ok, %Env{} = response} =
               call(request,
                 protocols: [:http2],
                 transport_opts: [cacertfile: upload_cacertfile]
               )

      assert response.status == 200
      assert response.body == Integer.to_string(chunk_count * 8_192)
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

  defp owned_port_count do
    Enum.count(:erlang.ports(), fn port ->
      :erlang.port_info(port, :connected) == {:connected, self()}
    end)
  end

  describe "HTTP/2 connection shared with another request" do
    setup do
      listener_ref = :"mint-shared-http2-#{System.unique_integer([:positive])}"
      priv_dir = :code.priv_dir(:httparrot)

      dispatch =
        :cowboy_router.compile([
          {:_,
           [
             {"/stream-reset", Tesla.TestSupport.MintInternalErrorRequestHandler, []},
             {"/upload", Tesla.TestSupport.MintUploadEchoHandler, []}
           ]}
        ])

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

      {:ok, conn} =
        Mint.HTTP.connect(:https, "localhost", port,
          protocols: [:http2],
          transport_opts: [cacertfile: httparrot_cacertfile()],
          mode: :passive
        )

      on_exit(fn -> Mint.HTTP.close(conn) end)

      {:ok, conn: conn, port: port, original: "localhost:#{port}"}
    end

    test "skips the reset of another request", %{conn: conn, port: port, original: original} do
      {:ok, conn, _reset_ref} = Mint.HTTP.request(conn, "GET", "/stream-reset", [], nil)
      Process.sleep(100)

      request = %Env{
        method: :post,
        url: "https://localhost:#{port}/upload",
        headers: [{"content-type", "text/plain"}],
        body: "hello"
      }

      assert {:ok, %Env{status: 200, body: "5"}} =
               call(request,
                 conn: conn,
                 original: original,
                 mode: :passive,
                 close_conn: false,
                 protocols: [:http2]
               )
    end

    test "skips the pong of another request", %{conn: conn, port: port, original: original} do
      {:ok, conn, _ping_ref} = Mint.HTTP2.ping(conn)

      request = %Env{
        method: :post,
        url: "https://localhost:#{port}/upload",
        headers: [{"content-type", "text/plain"}],
        body: "hello"
      }

      assert {:ok, %Env{status: 200, body: "5"}} =
               call(request,
                 conn: conn,
                 original: original,
                 mode: :passive,
                 close_conn: false,
                 protocols: [:http2]
               )
    end

    test "surfaces the error mint reported while sending an HTTP/2 body chunk", %{
      conn: conn,
      port: port,
      original: original
    } do
      socket = Mint.HTTP.get_socket(conn)

      body =
        Stream.map([:sent, :after_close], fn
          :sent ->
            String.duplicate("a", 100)

          :after_close ->
            :ssl.close(socket)
            String.duplicate("b", 100)
        end)

      request = %Env{
        method: :post,
        url: "https://localhost:#{port}/upload",
        headers: [{"content-type", "text/plain"}],
        body: body
      }

      assert {:error, %Mint.TransportError{reason: :closed}} ==
               call(request,
                 conn: conn,
                 original: original,
                 mode: :passive,
                 close_conn: false,
                 protocols: [:http2]
               )
    end
  end

  describe "cacert configured for the adapter" do
    setup do
      on_exit(fn -> Application.delete_env(:tesla, Tesla.Adapter.Mint) end)
      :ok
    end

    test "verifies the peer with the configured cacertfile" do
      Application.put_env(:tesla, Tesla.Adapter.Mint, cacert: httparrot_cacertfile())

      request = %Env{method: :get, url: "#{@https}/ip"}

      assert {:ok, %Env{status: 200}} = call(request)
    end

    test "adds the configured cacertfile to the transport options it was given" do
      Application.put_env(:tesla, Tesla.Adapter.Mint, cacert: httparrot_cacertfile())

      request = %Env{method: :get, url: "#{@https}/ip"}

      assert {:ok, %Env{status: 200}} = call(request, transport_opts: [depth: 3])
    end

    test "keeps the cacertfile the caller passed in transport options" do
      Application.put_env(:tesla, Tesla.Adapter.Mint, cacert: "/nonexistent/ca.crt")

      request = %Env{method: :get, url: "#{@https}/ip"}

      assert {:ok, %Env{status: 200}} =
               call(request, transport_opts: [cacertfile: httparrot_cacertfile()])
    end
  end

  describe "errors while receiving the response" do
    setup do
      uri = URI.parse(@http)
      {:ok, conn} = Mint.HTTP.connect(:http, uri.host, uri.port, mode: :active)
      on_exit(fn -> Mint.HTTP.close(conn) end)
      {:ok, conn: conn, original: "#{uri.host}:#{uri.port}", uri: uri}
    end

    test "gives up once no message arrives in time", %{conn: conn, original: original} do
      request = %Env{method: :get, url: "#{@http}/delay/2"}

      assert {:error, :timeout} ==
               call(request, conn: conn, original: original, close_conn: false, timeout: 100)
    end

    test "reports a message that belongs to another connection as unknown", %{
      conn: conn,
      original: original,
      uri: uri
    } do
      {:ok, other} = Mint.HTTP.connect(:http, uri.host, uri.port, mode: :active)
      on_exit(fn -> Mint.HTTP.close(other) end)

      send(self(), {:tcp, Mint.HTTP.get_socket(other), "not for this connection"})

      request = %Env{method: :get, url: "#{@http}/ip"}

      assert {:error, :unknown} ==
               call(request, conn: conn, original: original, close_conn: false)
    end

    test "surfaces the transport error mint reported", %{conn: conn, original: original} do
      send(self(), {:tcp_error, Mint.HTTP.get_socket(conn), :econnreset})

      request = %Env{method: :get, url: "#{@http}/ip"}

      assert {:error, "Encounter Mint error %Mint.TransportError{reason: :econnreset}"} ==
               call(request, conn: conn, original: original, close_conn: false)
    end

    test "skips the responses of another request on the same connection", %{uri: uri} do
      {:ok, conn} = Mint.HTTP.connect(:http, uri.host, uri.port, mode: :passive)
      on_exit(fn -> Mint.HTTP.close(conn) end)

      {:ok, conn, _pipelined_ref} = Mint.HTTP.request(conn, "GET", "/stream/100", [], nil)

      request = %Env{method: :get, url: "#{@http}/status/204"}

      assert {:ok, %Env{status: 204, body: nil} = response} =
               call(request,
                 conn: conn,
                 original: "#{uri.host}:#{uri.port}",
                 mode: :passive,
                 close_conn: false
               )

      refute Tesla.get_header(response, "transfer-encoding")
    end
  end

  describe "errors while sending the request" do
    setup do
      uri = URI.parse(@http)
      {:ok, uri: uri, original: "#{uri.host}:#{uri.port}"}
    end

    test "surfaces the error mint reported when opening a streamed request", %{
      uri: uri,
      original: original
    } do
      {:ok, conn} = Mint.HTTP.connect(:http, uri.host, uri.port, mode: :active)
      {:ok, conn, _in_flight_ref} = Mint.HTTP.request(conn, "POST", "/post", [], :stream)
      on_exit(fn -> Mint.HTTP.close(conn) end)

      request = %Env{
        method: :post,
        url: "#{@http}/post",
        headers: [{"content-type", "text/plain"}],
        body: Stream.map(["ab"], & &1)
      }

      assert {:error, %Mint.HTTPError{reason: :request_body_is_streaming, module: Mint.HTTP1}} ==
               call(request, conn: conn, original: original, close_conn: false)
    end

    test "surfaces the error mint reported when sending the request", %{
      uri: uri,
      original: original
    } do
      {:ok, conn} = Mint.HTTP.connect(:http, uri.host, uri.port, mode: :active)
      {:ok, conn, _in_flight_ref} = Mint.HTTP.request(conn, "POST", "/post", [], :stream)
      on_exit(fn -> Mint.HTTP.close(conn) end)

      request = %Env{
        method: :post,
        url: "#{@http}/post",
        headers: [{"content-type", "text/plain"}],
        body: "ab"
      }

      assert {:error, %Mint.HTTPError{reason: :request_body_is_streaming, module: Mint.HTTP1}} ==
               call(request, conn: conn, original: original, close_conn: false)
    end

    test "surfaces the error mint reported while sending a body chunk", %{
      uri: uri,
      original: original
    } do
      {:ok, conn} = Mint.HTTP.connect(:http, uri.host, uri.port, mode: :passive)
      socket = Mint.HTTP.get_socket(conn)

      body =
        Stream.map([:sent, :after_close], fn
          :sent ->
            "ab"

          :after_close ->
            :gen_tcp.close(socket)
            "cd"
        end)

      request = %Env{
        method: :post,
        url: "#{@http}/post",
        headers: [{"content-type", "text/plain"}],
        body: body
      }

      assert {:error, %Mint.TransportError{reason: :closed}} ==
               call(request,
                 conn: conn,
                 original: original,
                 mode: :passive,
                 close_conn: false
               )
    end
  end

  describe "request bodies streamed chunk by chunk" do
    test "skips the empty chunks the stream yields" do
      request = %Env{
        method: :post,
        url: "#{@http}/post",
        headers: [{"content-type", "text/plain"}],
        body: Stream.map(["", "ab", "", "cd"], & &1)
      }

      assert {:ok, %Env{} = response} = call(request)
      assert posted_data(response.body) == "abcd"
    end

    test "sends the bytes a stream of integers yields" do
      request = %Env{
        method: :post,
        url: "#{@http}/post",
        headers: [{"content-type", "text/plain"}],
        body: Stream.map(~c"abc", & &1)
      }

      assert {:ok, %Env{} = response} = call(request)
      assert posted_data(response.body) == "abc"
    end
  end

  describe "responses streamed over HTTP/1" do
    setup do
      listener_ref = :"mint-streamed-response-#{System.unique_integer([:positive])}"

      {:ok, _pid} =
        :cowboy.start_clear(listener_ref, [port: 0], %{env: %{dispatch: streamed_dispatch()}})

      on_exit(fn -> :cowboy.stop_listener(listener_ref) end)

      {_, port} = :ranch.get_addr(listener_ref)

      {:ok, port: port, url: "http://localhost:#{port}", original: "localhost:#{port}"}
    end

    test "appends the trailers to the response headers", %{url: url} do
      request = %Env{method: :get, url: "#{url}/trailers", headers: [{"te", "trailers"}]}

      assert {:ok, %Env{} = response} = call(request)
      assert response.body == "hello"
      assert Tesla.get_header(response, "content-type") == "text/plain"
      assert Tesla.get_header(response, "x-checksum") == "abc"
    end

    test "reports an empty chunk while the body is still pending", %{url: url} do
      request = %Env{method: :get, url: "#{url}/stalled"}

      assert {:ok, %Env{status: 200, body: %{body: {:nofin, ""}}}} =
               call(request, body_as: :chunks, close_conn: false)
    end

    test "emits every chunk a response delivered across packets", %{url: url} do
      request = %Env{method: :get, url: "#{url}/chunked"}

      assert {:ok, %Env{body: body}} = call(request, body_as: :stream)
      assert IO.iodata_to_binary(Enum.to_list(body)) == String.duplicate("chunk", 200)
    end

    test "waits for a packet that does not complete a chunk", %{
      url: url,
      port: port,
      original: original
    } do
      {:ok, conn} = Mint.HTTP.connect(:http, "localhost", port, mode: :active)
      on_exit(fn -> Mint.HTTP.close(conn) end)

      socket = Mint.HTTP.get_socket(conn)
      request = %Env{method: :get, url: "#{url}/stalled"}

      assert {:ok, %Env{body: body}} =
               call(request,
                 conn: conn,
                 original: original,
                 body_as: :stream,
                 close_conn: false
               )

      send(self(), {:tcp, socket, "5"})
      send(self(), {:tcp, socket, "\r\nhello\r\n"})
      send(self(), {:tcp, socket, "0\r\n\r\n"})

      assert Enum.to_list(body) == ["hello"]
    end

    test "raises the timeout the body stream waited on", %{
      url: url,
      port: port,
      original: original
    } do
      {:ok, conn} = Mint.HTTP.connect(:http, "localhost", port, mode: :active)
      on_exit(fn -> Mint.HTTP.close(conn) end)

      request = %Env{method: :get, url: "#{url}/stalled"}

      assert {:ok, %Env{body: body}} =
               call(request,
                 conn: conn,
                 original: original,
                 body_as: :stream,
                 close_conn: false,
                 timeout: 200
               )

      assert_raise RuntimeError, ":timeout", fn -> Enum.to_list(body) end
    end

    test "raises the transport error the body stream hit", %{
      url: url,
      port: port,
      original: original
    } do
      {:ok, conn} = Mint.HTTP.connect(:http, "localhost", port, mode: :active)
      on_exit(fn -> Mint.HTTP.close(conn) end)

      socket = Mint.HTTP.get_socket(conn)
      request = %Env{method: :get, url: "#{url}/stalled"}

      assert {:ok, %Env{body: body}} =
               call(request,
                 conn: conn,
                 original: original,
                 body_as: :stream,
                 close_conn: false
               )

      send(self(), {:tcp_error, socket, :econnreset})

      assert_raise RuntimeError,
                   "Encounter Mint error %Mint.TransportError{reason: :econnreset}",
                   fn -> Enum.to_list(body) end
    end
  end

  defp streamed_dispatch do
    :cowboy_router.compile([
      {:_,
       [
         {"/chunked", Tesla.TestSupport.MintChunkedBodyHandler, []},
         {"/stalled", Tesla.TestSupport.MintStalledBodyHandler, []},
         {"/trailers", Tesla.TestSupport.MintTrailersHandler, []}
       ]}
    ])
  end

  defp early_response_dispatch do
    :cowboy_router.compile([
      {:_, [{"/early-response", Tesla.TestSupport.MintEarlyResponseHandler, []}]}
    ])
  end

  defp upload_echo_dispatch do
    :cowboy_router.compile([
      {:_, [{"/upload", Tesla.TestSupport.MintUploadEchoHandler, []}]}
    ])
  end
end
