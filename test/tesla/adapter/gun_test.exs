defmodule ReplyToCollector do
  def collect(message, pid), do: send(pid, {:collected, message})
end

defmodule Tesla.Adapter.GunTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Gun
  use Tesla.AdapterCase.Basic, connection_refused_reason: :timeout
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.Query

  use Tesla.AdapterCase.SSL,
    certificates_verification: true,
    transport_opts: [
      cacertfile: Path.join([to_string(:code.priv_dir(:httparrot)), "/ssl/server-ca.crt"])
    ]

  alias Tesla.Adapter.Gun

  import ExUnit.CaptureLog

  @gun2 Application.spec(:gun, :vsn) |> List.to_string() |> Version.match?("~> 2.0")

  test "fallback adapter timeout option" do
    request = %Env{
      method: :get,
      url: "#{@http}/delay/2"
    }

    assert {:error, :recv_response_timeout} = call(request, timeout: 1_000)
  end

  test "max_body option" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/100"
    }

    assert {:error, :body_too_large} = call(request, max_body: 5)
  end

  test "url without path" do
    request = %Env{
      method: :get,
      url: "#{@http}"
    }

    assert {:ok, %Env{status: 200}} = call(request)
  end

  test "url without path, but with query" do
    request = %Env{
      method: :get,
      url: "#{@http}",
      query: [
        param: "value"
      ]
    }

    assert {:ok, %Env{status: 200} = _response} = call(request)
  end

  test "ipv4 request" do
    request = %Env{
      method: :get,
      url: "http://127.0.0.1:#{Application.get_env(:httparrot, :http_port)}/stream-bytes/10"
    }

    assert {:ok, %Env{status: 200, body: body}} = call(request)
    assert byte_size(body) == 16
  end

  test "response stream" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{status: 200, body: body}} = call(request)
    assert byte_size(body) == 16
  end

  test "response body as stream" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{status: 200, body: stream}} = call(request, body_as: :stream)
    assert is_function(stream)
    assert stream |> Enum.join() |> byte_size() == 16
  end

  test "response body as chunks with closing connection" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{status: 200, body: %{pid: pid, stream: stream, opts: opts}}} =
             call(request, body_as: :chunks)

    assert is_pid(pid)
    assert is_reference(stream)

    assert read_body(pid, stream, opts) |> byte_size() == 16
    refute Process.alive?(pid)
  end

  test "certificates_verification option" do
    request = %Env{
      method: :get,
      url: "#{@https}"
    }

    assert {:ok, %Env{} = _response} =
             call(request,
               certificates_verification: true,
               transport_opts: [
                 cacertfile: "#{:code.priv_dir(:httparrot)}/ssl/server-ca.crt"
               ]
             )
  end

  describe "reusing connection" do
    setup do
      uri = URI.parse(@http)
      {:ok, conn} = :gun.open(to_charlist(uri.host), uri.port)

      request = %Env{
        method: :get,
        url: "#{@http}/stream-bytes/10"
      }

      on_exit(fn -> Gun.close(conn) end)

      {:ok, request: request, conn: conn}
    end

    test "response body as plain", %{request: request, conn: conn} do
      assert {:ok, %Env{status: 200, body: body}} = call(request, conn: conn, close_conn: false)
      assert byte_size(body) == 16
      assert Process.alive?(conn)
    end

    test "response body as chunks", %{request: request, conn: conn} do
      opts = [body_as: :chunks, conn: conn, close_conn: false]

      assert {:ok, %Env{status: 200, body: %{pid: pid, stream: stream}}} = call(request, opts)

      assert is_pid(pid)
      assert is_reference(stream)
      assert conn == pid

      assert read_body(pid, stream, opts) |> byte_size() == 16
      assert Process.alive?(pid)
    end

    test "response body as stream without closing connection", %{request: request, conn: conn} do
      assert {:ok, %Env{status: 200, body: stream}} =
               call(request, body_as: :stream, conn: conn, close_conn: false)

      assert is_function(stream)
      assert stream |> Enum.join() |> byte_size() == 16

      assert Process.alive?(conn)
    end

    test "response body as stream with closing connection", %{request: request, conn: conn} do
      assert {:ok, %Env{status: 200, body: stream}} = call(request, body_as: :stream, conn: conn)

      assert is_function(stream)
      assert stream |> Enum.join() |> byte_size() == 16

      refute Process.alive?(conn)
    end

    test "opened to another domain", %{request: request, conn: conn} do
      new_url = "http://127.0.0.1:#{Application.get_env(:httparrot, :http_port)}/stream-bytes/10"
      assert {:error, :invalid_conn} = call(Map.put(request, :url, new_url), conn: conn)
    end

    test "opened to another port", %{request: request, conn: conn} do
      uri = URI.parse(@https)
      new_url = "http://#{uri.host}:#{uri.port}/stream-bytes/10"

      assert {:error, :invalid_conn} = call(Map.put(request, :url, new_url), conn: conn)
    end

    test "opened for another scheme on the same host and port", %{request: request} do
      uri = URI.parse(@https)

      tls_opts_key = if @gun2, do: :tls_opts, else: :transport_opts

      {:ok, conn} =
        :gun.open(to_charlist(uri.host), uri.port, %{
          :transport => :tls,
          tls_opts_key => [verify: :verify_none]
        })

      on_exit(fn -> Gun.close(conn) end)

      new_url = "http://#{uri.host}:#{uri.port}/stream-bytes/10"

      assert {:error, :invalid_conn} = call(Map.put(request, :url, new_url), conn: conn)
    end
  end

  test "error response" do
    request = %Env{
      method: :get,
      url: "#{@http}/status/500"
    }

    assert {:ok, %Env{} = response} = call(request, timeout: 1_000)
    assert response.status == 500
  end

  test "receive gun_up message when receive is false" do
    request = %Env{
      method: :get,
      url: "#{@http}"
    }

    assert {:ok, %Env{} = response} = call(request, receive: false)
    assert response.status == 200
    assert_receive {:gun_up, pid, :http}
    assert is_pid(pid)
  end

  test "passes explicit pid reply_to through to gun on plain responses" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    test_pid = self()

    reply_to =
      spawn(fn ->
        receive do
          message -> send(test_pid, {:gun_reply_to, message})
        end
      end)

    assert {:error, :recv_response_timeout} = call(request, reply_to: reply_to, timeout: 100)

    assert_receive {:gun_reply_to, {:gun_response, pid, stream, :nofin, 200, _headers}}
    assert is_pid(pid)
    assert is_reference(stream)
  end

  test "preserves explicit function reply_to when stream ownership is handed off" do
    test_pid = self()

    # The requesting process owns the gun connection, so it has to outlive the
    # stream. Keeping it in the test process and spawning the stream owner
    # instead avoids racing the connection teardown against the last chunk.
    stream_owner = spawn(fn -> forward_messages(test_pid) end)
    on_exit(fn -> Process.exit(stream_owner, :kill) end)

    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10",
      private: %{tesla_gun_stream_owner: stream_owner}
    }

    reply_to = fn message -> send(test_pid, {:gun_reply_to, message}) end

    assert {:ok, %Env{status: 200, body: %{pid: pid, stream: stream}}} =
             Tesla.Adapter.Gun.call(request,
               body_as: :chunks,
               reply_to: reply_to,
               timeout: 5_000
             )

    assert_receive {:gun_reply_to, {:gun_response, ^pid, ^stream, :nofin, 200, _headers}}
    assert is_pid(pid)
    assert is_reference(stream)
    assert_receive {:gun_reply_to, {:gun_data, ^pid, ^stream, _, _}}
    assert_receive {:stream_owner, {:gun_data, ^pid, ^stream, _, _}}
    assert_receive {:gun_data, ^pid, ^stream, _, _}

    Gun.close(pid)
  end

  test "keeps the reply_to untouched when the stream owner is the request owner" do
    test_pid = self()

    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10",
      private: %{tesla_gun_stream_owner: test_pid}
    }

    reply_to = spawn_forwarder(test_pid, :reply_to)
    on_exit(fn -> Process.exit(reply_to, :kill) end)

    assert {:error, :recv_response_timeout} =
             call(request, body_as: :chunks, reply_to: reply_to, timeout: 100)

    assert_receive {:reply_to, {:gun_response, pid, stream, :nofin, 200, _headers}}
    assert_receive {:reply_to, {:gun_data, ^pid, ^stream, _, _}}
    refute_received {:gun_response, ^pid, ^stream, :nofin, 200, _headers}

    Gun.close(pid)
  end

  test "routes to a pid reply_to when stream ownership is handed off" do
    test_pid = self()

    stream_owner = spawn_forwarder(test_pid, :stream_owner)
    reply_to = spawn_forwarder(test_pid, :reply_to)
    on_exit(fn -> Enum.each([stream_owner, reply_to], &Process.exit(&1, :kill)) end)

    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10",
      private: %{tesla_gun_stream_owner: stream_owner}
    }

    assert {:ok, %Env{status: 200, body: %{pid: pid, stream: stream}}} =
             call(request, body_as: :chunks, reply_to: reply_to, timeout: 5_000)

    assert_receive {:reply_to, {:gun_response, ^pid, ^stream, :nofin, 200, _headers}}
    assert_receive {:reply_to, {:gun_data, ^pid, ^stream, _, _}}
    assert_receive {:stream_owner, {:gun_data, ^pid, ^stream, _, _}}
    assert_receive {:gun_data, ^pid, ^stream, _, _}

    Gun.close(pid)
  end

  test "routes to a module function reply_to when stream ownership is handed off" do
    test_pid = self()

    stream_owner = spawn_forwarder(test_pid, :stream_owner)
    on_exit(fn -> Process.exit(stream_owner, :kill) end)

    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10",
      private: %{tesla_gun_stream_owner: stream_owner}
    }

    assert {:ok, %Env{status: 200, body: %{pid: pid, stream: stream}}} =
             call(request,
               body_as: :chunks,
               reply_to: {ReplyToCollector, :collect, [test_pid]},
               timeout: 5_000
             )

    assert_receive {:collected, {:gun_response, ^pid, ^stream, :nofin, 200, _headers}}
    assert_receive {:collected, {:gun_data, ^pid, ^stream, _, _}}

    Gun.close(pid)
  end

  test "routes to a function reply_to carrying extra arguments" do
    test_pid = self()

    stream_owner = spawn_forwarder(test_pid, :stream_owner)
    on_exit(fn -> Process.exit(stream_owner, :kill) end)

    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10",
      private: %{tesla_gun_stream_owner: stream_owner}
    }

    collect = fn message, pid -> send(pid, {:collected, message}) end

    assert {:ok, %Env{status: 200, body: %{pid: pid, stream: stream}}} =
             call(request, body_as: :chunks, reply_to: {collect, [test_pid]}, timeout: 5_000)

    assert_receive {:collected, {:gun_response, ^pid, ^stream, :nofin, 200, _headers}}
    assert_receive {:collected, {:gun_data, ^pid, ^stream, _, _}}

    Gun.close(pid)
  end

  test "delivers once when the reply_to is also the stream owner" do
    test_pid = self()

    stream_owner = spawn_forwarder(test_pid, :stream_owner)
    on_exit(fn -> Process.exit(stream_owner, :kill) end)

    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10",
      private: %{tesla_gun_stream_owner: stream_owner}
    }

    assert {:ok, %Env{status: 200, body: %{pid: pid, stream: stream}}} =
             call(request, body_as: :chunks, reply_to: stream_owner, timeout: 5_000)

    assert_receive {:stream_owner, {:gun_response, ^pid, ^stream, :nofin, 200, _headers}}
    assert_receive {:stream_owner, {:gun_data, ^pid, ^stream, :fin, _}}

    refute_receive {:stream_owner, {:gun_data, ^pid, ^stream, :fin, _}}

    Gun.close(pid)
  end

  test "relays a stream error to the request owner, the reply_to and the stream owner" do
    test_pid = self()

    url =
      start_raw_server(fn socket ->
        :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
        Process.sleep(50)
        :gen_tcp.close(socket)
      end)

    stream_owner = spawn_forwarder(test_pid, :stream_owner)
    on_exit(fn -> Process.exit(stream_owner, :kill) end)

    request = %Env{
      method: :get,
      url: url,
      private: %{tesla_gun_stream_owner: stream_owner}
    }

    reply_to = fn message -> send(test_pid, {:gun_reply_to, message}) end

    assert {:ok, %Env{status: 200, body: %{pid: pid, stream: stream}}} =
             call(request, body_as: :chunks, reply_to: reply_to, timeout: 2_000)

    assert_receive {:gun_error, ^pid, ^stream, reason}, 1_000
    assert_receive {:gun_reply_to, {:gun_error, ^pid, ^stream, ^reason}}, 1_000
    assert_receive {:stream_owner, {:gun_error, ^pid, ^stream, ^reason}}, 1_000

    Gun.close(pid)
  end

  test "reports the monitor reason when a process goes down while the body is read" do
    victim = spawn(fn -> Process.sleep(:infinity) end)
    Process.monitor(victim)

    url =
      start_raw_server(fn socket ->
        :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
        Process.sleep(150)
        Process.exit(victim, :kill)
        Process.sleep(2_000)
      end)

    request = %Env{method: :get, url: url}

    assert {:error, :killed} == call(request, timeout: 2_000)
  end

  test "keeps waiting for the response while the connection goes down and back up" do
    url = start_raw_server(fn socket -> :gen_tcp.close(socket) end, accept: :forever)

    request = %Env{method: :get, url: url}

    assert {:error, :recv_response_timeout} ==
             call(request, timeout: 1_500, retry: 5, retry_timeout: 50)
  end

  # Leaves the caller holding a response stream with nothing left to read and an
  # empty mailbox, so a test can decide what the next chunk read finds there.
  defp drained_response_stream do
    uri = URI.parse(@http)
    {:ok, conn} = :gun.open(to_charlist(uri.host), uri.port)
    {:ok, _} = :gun.await_up(conn)
    on_exit(fn -> Gun.close(conn) end)

    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{status: 200, body: stream}} =
             call(request, body_as: :stream, conn: conn, close_conn: false, timeout: 100)

    Process.sleep(200)
    :ok = :gun.flush(conn)

    stream
  end

  test "streams a chunked body that arrives in more than one part" do
    url =
      start_raw_server(fn socket ->
        :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
        Process.sleep(50)
        :gen_tcp.send(socket, "5\r\nfirst\r\n")
        Process.sleep(50)
        :gen_tcp.send(socket, "6\r\nsecond\r\n")
        Process.sleep(50)
        :gen_tcp.send(socket, "0\r\n\r\n")
        Process.sleep(50)
        :gen_tcp.close(socket)
      end)

    request = %Env{method: :get, url: url}

    assert {:ok, %Env{status: 200, body: stream}} =
             call(request, body_as: :stream, timeout: 2_000)

    assert Enum.join(stream) == "firstsecond"
  end

  defp start_raw_server(on_request, opts \\ []) do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen_socket)

    server =
      spawn(fn ->
        accept = fn accept ->
          with {:ok, socket} <- :gen_tcp.accept(listen_socket),
               {:ok, _request} <- :gen_tcp.recv(socket, 0, 5_000) do
            on_request.(socket)
          end

          if opts[:accept] == :forever, do: accept.(accept)
        end

        accept.(accept)
      end)

    on_exit(fn ->
      Process.exit(server, :kill)
      :gen_tcp.close(listen_socket)
    end)

    "http://127.0.0.1:#{port}/raw"
  end

  defp spawn_forwarder(test_pid, tag) do
    spawn(fn -> forward_messages(test_pid, tag) end)
  end

  defp forward_messages(test_pid, tag) do
    receive do
      message ->
        send(test_pid, {tag, message})
        forward_messages(test_pid, tag)
    end
  end

  defp forward_messages(test_pid) do
    receive do
      message ->
        send(test_pid, {:stream_owner, message})
        forward_messages(test_pid)
    end
  end

  test "on TLS errors get timeout error from await_up method" do
    request = %Env{
      method: :get,
      url: "#{@https}"
    }

    log =
      capture_log(fn ->
        {time, resp} =
          :timer.tc(fn ->
            call(request,
              timeout: 60_000,
              certificates_verification: true
            )
          end)

        assert resp == {:error, :timeout}

        assert time / 1_000_000 < 6
      end)

    assert log =~ "Unknown CA"
  end

  # Gun 1.0 backwards compatibility tests
  if not @gun2 do
    test "error on socks proxy" do
      request = %Env{
        method: :get,
        url: "#{@http}/status/500"
      }

      assert {:error, "socks protocol is not supported"} ==
               call(request, proxy: {:socks5, ~c"localhost", 1234})
    end
  end

  describe "read_chunk/3" do
    test "returns the error gun reported for the stream" do
      stream = make_ref()
      send(self(), {:gun_error, self(), stream, :closed})

      assert {:error, :closed} == Gun.read_chunk(self(), stream, close_conn: false)
    end

    test "returns the reason the connection went down" do
      stream = make_ref()
      send(self(), {:DOWN, make_ref(), :process, self(), :killed})

      assert {:error, :killed} == Gun.read_chunk(self(), stream, close_conn: false)
    end
  end

  test "returns the option error gun rejected the connection with" do
    request = %Env{
      method: :get,
      url: "#{@http}/ip"
    }

    assert {:error, {:options, {:protocols, [:bogus]}}} == call(request, protocols: [:bogus])
  end

  test "raises when the response stream stops receiving chunks" do
    stream = drained_response_stream()

    assert_raise RuntimeError, ":recv_chunk_timeout", fn -> Enum.join(stream) end
  end

  test "reraises the exception the response stream failed with" do
    stream = drained_response_stream()
    send(self(), {:DOWN, make_ref(), :process, self(), %RuntimeError{message: "connection died"}})

    assert_raise RuntimeError, "connection died", fn -> Enum.join(stream) end
  end

  test "raises the message the response stream failed with" do
    stream = drained_response_stream()
    send(self(), {:DOWN, make_ref(), :process, self(), "connection died"})

    assert_raise RuntimeError, "connection died", fn -> Enum.join(stream) end
  end

  test "reuses a connection opened to an ip address" do
    {:ok, conn} = :gun.open({127, 0, 0, 1}, Application.get_env(:httparrot, :http_port))
    {:ok, _} = :gun.await_up(conn)
    on_exit(fn -> Gun.close(conn) end)

    request = %Env{
      method: :get,
      url: "http://127.0.0.1:#{Application.get_env(:httparrot, :http_port)}/ip"
    }

    assert {:ok, %Env{status: 200}} = call(request, conn: conn, close_conn: false)
    assert Process.alive?(conn)
  end

  test "streams a request body given as a bare enumerable function" do
    body =
      Stream.unfold(5, fn
        0 -> nil
        n -> {to_string(n), n - 1}
      end)

    assert is_function(body)

    request = %Env{
      method: :post,
      url: "#{@http}/post",
      headers: [{"content-type", "text/plain"}],
      body: body
    }

    assert {:ok, %Env{status: 200} = response} = call(request)
    assert response.body |> Jason.decode!() |> Map.fetch!("data") == "54321"
  end

  test "reads the tls options from the tls_opts key" do
    request = %Env{
      method: :get,
      url: "#{@https}"
    }

    assert {:ok, %Env{status: 200}} =
             call(request,
               tls_opts: [
                 verify: :verify_peer,
                 cacertfile: "#{:code.priv_dir(:httparrot)}/ssl/server-ca.crt"
               ]
             )
  end

  test "returns the connection error gun reported while reading the response" do
    uri = URI.parse(@http)
    {:ok, conn} = :gun.open(to_charlist(uri.host), uri.port)
    {:ok, _} = :gun.await_up(conn)
    on_exit(fn -> Gun.close(conn) end)

    request = %Env{method: :get, url: "#{@http}/ip"}

    send(self(), {:gun_error, conn, :boom})

    assert {:error, :boom} == call(request, conn: conn, close_conn: false)
  end

  test "returns the reason the connection went down while reading the response" do
    uri = URI.parse(@http)
    {:ok, conn} = :gun.open(to_charlist(uri.host), uri.port)
    {:ok, _} = :gun.await_up(conn)
    on_exit(fn -> Gun.close(conn) end)

    request = %Env{method: :get, url: "#{@http}/ip"}

    send(self(), {:DOWN, make_ref(), :process, conn, :killed})

    assert {:error, :killed} == call(request, conn: conn, close_conn: false)
  end

  describe "proxy" do
    setup do
      {:ok, http_port: Application.get_env(:httparrot, :http_port)}
    end

    test "returns unauthorized when the proxy forbids the tunnel", %{http_port: http_port} do
      proxy = start_tcp_proxy({:reject, 403, "Forbidden"})
      request = %Env{method: :get, url: "#{@http}/ip"}

      assert {:error, :unauthorized} == call(request, proxy: proxy, timeout: 2_000)

      assert_receive {:tcp_proxy_request, connect}
      assert connect =~ "CONNECT localhost:#{http_port} HTTP/1.1"
      refute connect =~ "proxy-authorization"
    end

    test "sends the tunnel credentials it was given" do
      proxy = start_tcp_proxy({:reject, 407, "Proxy Authentication Required"})
      request = %Env{method: :get, url: "#{@http}/ip"}

      assert {:error, :proxy_auth_failed} ==
               call(request, proxy: proxy, proxy_auth: {"user", "pass"}, timeout: 2_000)

      credentials = Base.encode64("user:pass")

      assert_receive {:tcp_proxy_request, connect}
      assert connect =~ "proxy-authorization: Basic #{credentials}"
    end

    test "asks the proxy to tunnel the https target" do
      proxy = start_tcp_proxy({:reject, 500, "Internal Server Error"})
      request = %Env{method: :get, url: "#{@https}/ip"}

      assert {:response, :nofin, 500, _headers} = call(request, proxy: proxy, timeout: 2_000)

      assert_receive {:tcp_proxy_request, connect}
      assert connect =~ "CONNECT localhost:#{Application.get_env(:httparrot, :https_port)}"
    end

    if @gun2 do
      test "surfaces the socks version gun rejected" do
        request = %Env{method: :get, url: "#{@http}/ip"}
        proxy = {:socks4, ~c"localhost", Application.get_env(:httparrot, :http_port)}

        assert {:error, {:options, {:socks, {:version, 4}}}} ==
                 call(request, proxy: proxy, retry: 0, connect_timeout: 500, timeout: 1_000)
      end

      test "opens a socks5 tunnel" do
        request = %Env{method: :get, url: "#{@http}/ip"}
        proxy = {:socks5, ~c"localhost", Application.get_env(:httparrot, :http_port)}

        assert {:error, :recv_response_timeout} ==
                 call(request, proxy: proxy, retry: 0, connect_timeout: 500, timeout: 500)
      end

      test "offers username password authentication with the proxy credentials" do
        proxy = start_socks5_server()
        request = %Env{method: :get, url: "#{@http}/ip"}

        assert {:error, :recv_response_timeout} ==
                 call(request,
                   proxy: proxy,
                   proxy_auth: {"user", "pass"},
                   retry: 0,
                   connect_timeout: 1_000,
                   timeout: 1_000
                 )

        assert_receive {:socks5_methods, <<0x02>>}
        assert_receive {:socks5_credentials, "user", "pass"}
      end

      test "offers no authentication without proxy credentials" do
        proxy = start_socks5_server()
        request = %Env{method: :get, url: "#{@http}/ip"}

        assert {:error, :recv_response_timeout} ==
                 call(request, proxy: proxy, retry: 0, connect_timeout: 1_000, timeout: 1_000)

        assert_receive {:socks5_methods, <<0x00>>}
      end

      test "merges the socks options it was given over the tunnel defaults" do
        request = %Env{method: :get, url: "#{@http}/ip"}
        proxy = {:socks5, ~c"localhost", Application.get_env(:httparrot, :http_port)}

        assert {:error, {:options, {:socks, {:version, 4}}}} ==
                 call(request,
                   proxy: proxy,
                   socks_opts: %{version: 4},
                   retry: 0,
                   connect_timeout: 500,
                   timeout: 500
                 )
      end
    end
  end

  # Speaks just enough of RFC 1928 and RFC 1929 to report back what the adapter
  # negotiated, then leaves the tunnel hanging so the request times out.
  defp start_socks5_server do
    test_pid = self()

    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen_socket)

    server =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)

        {:ok, <<0x05, count>>} = :gen_tcp.recv(socket, 2, 5_000)
        {:ok, methods} = :gen_tcp.recv(socket, count, 5_000)
        send(test_pid, {:socks5_methods, methods})

        if methods == <<0x02>> do
          :gen_tcp.send(socket, <<0x05, 0x02>>)

          {:ok, <<0x01, username_length>>} = :gen_tcp.recv(socket, 2, 5_000)
          {:ok, username} = :gen_tcp.recv(socket, username_length, 5_000)
          {:ok, <<password_length>>} = :gen_tcp.recv(socket, 1, 5_000)
          {:ok, password} = :gen_tcp.recv(socket, password_length, 5_000)
          send(test_pid, {:socks5_credentials, username, password})

          :gen_tcp.send(socket, <<0x01, 0x00>>)
        else
          :gen_tcp.send(socket, <<0x05, 0x00>>)
        end

        Process.sleep(:infinity)
      end)

    on_exit(fn ->
      Process.exit(server, :kill)
      :gen_tcp.close(listen_socket)
    end)

    {:socks5, ~c"127.0.0.1", port}
  end

  defp start_tcp_proxy(on_connect) do
    {:ok, pid, port} =
      Tesla.TestSupport.TcpProxy.start(report_to: self(), on_connect: on_connect)

    on_exit(fn -> Process.exit(pid, :kill) end)

    {~c"127.0.0.1", port}
  end

  defp read_body(pid, stream, opts, acc \\ "") do
    case Gun.read_chunk(pid, stream, opts) do
      {:fin, body} ->
        acc <> body

      {:nofin, part} ->
        read_body(pid, stream, opts, acc <> part)
    end
  end
end
