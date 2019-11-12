defmodule Tesla.Adapter.GunTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Gun
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.SSL
  alias Tesla.Adapter.Gun

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

  test "query without path" do
    request = %Env{
      method: :get,
      url: "#{@http}"
    }

    assert {:ok, %Env{} = response} = call(request)
    assert response.status == 200
  end

  test "query without path with query" do
    request = %Env{
      method: :get,
      url: "#{@http}",
      query: [
        param: "value"
      ]
    }

    assert {:ok, %Env{} = response} = call(request)
    assert response.status == 200
  end

  test "response stream" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} = call(request)
    assert response.status == 200
    assert byte_size(response.body) == 16
  end

  test "read response body in chunks" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} = call(request, body_as: :chunks)
    assert response.status == 200
    %{pid: pid, stream: stream, opts: opts} = response.body
    assert opts[:body_as] == :chunks
    assert is_pid(pid)
    assert is_reference(stream)

    assert read_body(pid, stream, opts) |> byte_size() == 16
    refute Process.alive?(pid)
  end

  test "read response body in chunks with closing connection by default opts" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} = call(request, body_as: :chunks)
    assert response.status == 200
    %{pid: pid, stream: stream, opts: opts} = response.body
    assert opts[:body_as] == :chunks
    assert is_pid(pid)
    assert is_reference(stream)

    assert read_body(pid, stream, opts) |> byte_size() == 16
    refute Process.alive?(pid)
  end

  test "with body_as :plain reusing connection" do
    uri = URI.parse(@http)
    {:ok, conn} = :gun.open(to_charlist(uri.host), uri.port)

    original = "#{uri.host}:#{uri.port}"

    request = %Env{
      method: :get,
      url: "#{@http}/ip"
    }

    assert {:ok, %Env{} = response} =
             call(request, conn: conn, close_conn: false, original: original)

    assert response.status == 200
    assert Process.alive?(conn)

    assert {:ok, %Env{} = response} =
             call(request, conn: conn, close_conn: false, original: original)

    assert response.status == 200
    assert Process.alive?(conn)
    :ok = Gun.close(conn)
    refute Process.alive?(conn)
  end

  test "read response body in chunks with reused connection and closing it" do
    uri = URI.parse(@http)
    {:ok, conn} = :gun.open(to_charlist(uri.host), uri.port)

    original = "#{uri.host}:#{uri.port}"

    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} =
             call(request, body_as: :chunks, conn: conn, original: original, close_conn: false)

    assert response.status == 200
    %{pid: pid, stream: stream, opts: opts} = response.body
    assert opts[:body_as] == :chunks
    assert is_pid(pid)
    assert is_reference(stream)
    assert conn == pid

    assert read_body(pid, stream, opts) |> byte_size() == 16
    assert Process.alive?(pid)

    # reusing connection
    assert {:ok, %Env{} = response} =
             call(request, body_as: :chunks, conn: conn, original: original, close_conn: false)

    assert response.status == 200
    %{pid: pid, stream: stream, opts: opts} = response.body
    assert opts[:body_as] == :chunks
    assert is_pid(pid)
    assert is_reference(stream)
    assert conn == pid

    assert read_body(pid, stream, opts) |> byte_size() == 16
    assert Process.alive?(pid)

    :ok = Gun.close(pid)
    refute Process.alive?(pid)
  end

  test "don't reuse connection if original does not match" do
    uri = URI.parse(@http)
    {:ok, conn} = :gun.open(to_charlist(uri.host), uri.port)

    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} =
             call(request, body_as: :chunks, conn: conn, original: "example.com:80")

    assert response.status == 200
    %{pid: pid, stream: stream, opts: opts} = response.body
    assert opts[:body_as] == :chunks
    assert is_pid(pid)
    assert is_reference(stream)

    assert read_body(pid, stream, opts) |> byte_size() == 16
    refute Process.alive?(pid)
    refute conn == pid
  end

  test "don't reuse connection and verify fun if original does not match in https request" do
    uri = URI.parse(@https)

    host = to_charlist(uri.host)

    {:ok, conn} = :gun.open(host, uri.port)

    request = %Env{
      method: :get,
      url: "#{@https}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} =
             call(request,
               body_as: :chunks,
               conn: conn,
               original: "example.com:443",
               transport_opts: [
                 verify_fun: {&:ssl_verify_hostname.verify_fun/3, [check_hostname: 'example.com']}
               ]
             )

    assert response.status == 200
    %{pid: pid, stream: stream, opts: opts} = response.body

    assert is_pid(pid)
    assert is_reference(stream)

    assert read_body(pid, stream, opts) |> byte_size() == 16

    refute Process.alive?(pid)
    assert opts[:old_conn] == conn
    refute conn == pid
  end

  test "certificates_verification" do
    request = %Env{
      method: :get,
      url: "#{@https}"
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
  end

  test "certificates_verification with domain" do
    request = %Env{
      method: :get,
      url: "https://localhost:5443"
    }

    assert {:ok, %Env{} = response} =
             call(request,
               certificates_verification: true,
               transport_opts: [
                 cacertfile: "./deps/httparrot/priv/ssl/server-ca.crt"
               ]
             )
  end

  test "read response body in stream" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} = call(request, body_as: :stream)
    assert response.status == 200
    assert is_function(response.body)
    assert Enum.join(response.body) |> byte_size() == 16
  end

  test "read response body in stream with opened connection without closing connection" do
    uri = URI.parse(@http)
    {:ok, conn} = :gun.open(to_charlist(uri.host), uri.port)
    original = "#{uri.host}:#{uri.port}"

    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} =
             call(request, body_as: :stream, conn: conn, close_conn: false, original: original)

    assert response.status == 200
    assert is_function(response.body)
    assert Enum.join(response.body) |> byte_size() == 16

    assert Process.alive?(conn)

    :ok = Gun.close(conn)
    refute Process.alive?(conn)
  end

  test "read response body in stream with opened connection with closing connection" do
    uri = URI.parse(@http)
    {:ok, conn} = :gun.open(to_charlist(uri.host), uri.port)

    original = "#{uri.host}:#{uri.port}"

    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} =
             call(request, body_as: :stream, conn: conn, original: original)

    assert response.status == 200
    assert is_function(response.body)
    assert Enum.join(response.body) |> byte_size() == 16

    refute Process.alive?(conn)
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

  test "ipv4" do
    request = %Env{
      method: :get,
      url: "http://0.0.0.0:5080/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} = call(request, body_as: :chunks, original: "localhost:5080")
    assert response.status == 200
    %{pid: pid, stream: stream, opts: opts} = response.body
    assert %{origin_host: {0, 0, 0, 0}} = :gun.info(pid)
    assert opts[:original_matches] == false
    assert read_body(pid, stream, opts) |> byte_size() == 16
  end

  test "original does not match" do
    request = %Env{
      method: :get,
      url: "http://localhost:5080/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} = call(request, body_as: :chunks, original: "0.0.0.0:5080")
    assert response.status == 200
    %{pid: pid, stream: stream, opts: opts} = response.body
    assert %{origin_host: 'localhost'} = :gun.info(pid)
    assert opts[:original_matches] == false
    assert read_body(pid, stream, opts) |> byte_size() == 16
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
