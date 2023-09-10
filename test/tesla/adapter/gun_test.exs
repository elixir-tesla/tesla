defmodule Tesla.Adapter.GunTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Gun
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody

  use Tesla.AdapterCase.SSL,
    certificates_verification: true,
    transport_opts: [
      cacertfile: Path.join([to_string(:code.priv_dir(:httparrot)), "/ssl/server-ca.crt"])
    ]

  alias Tesla.Adapter.Gun

  import ExUnit.CaptureLog

  setup do
    on_exit(fn -> assert Supervisor.which_children(:gun_sup) == [] end)
  end

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
  end

  test "error response" do
    request = %Env{
      method: :get,
      url: "#{@http}/status/500"
    }

    assert {:ok, %Env{} = response} = call(request, timeout: 1_000)
    assert response.status == 500
  end

  test "error on socks proxy" do
    request = %Env{
      method: :get,
      url: "#{@http}/status/500"
    }

    assert {:error, "socks protocol is not supported"} ==
             call(request, proxy: {:socks5, 'localhost', 1234})
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

  defp read_body(pid, stream, opts, acc \\ "") do
    case Gun.read_chunk(pid, stream, opts) do
      {:fin, body} ->
        acc <> body

      {:nofin, part} ->
        read_body(pid, stream, opts, acc <> part)
    end
  end
end
