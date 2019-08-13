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

    assert {:error, :timeout} = call(request, timeout: 1_000)
  end

  test "max_body option" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/100",
      query: [
        message: "Hello world!"
      ]
    }

    assert {:error, :body_too_large} = call(request, max_body: 5)
  end

  test "without slash" do
    request = %Env{
      method: :get,
      url: "#{@http}"
    }

    assert {:ok, %Env{} = response} = call(request)
    assert response.status == 400
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

    assert read_body(pid, stream) |> byte_size() == 16
    refute Process.alive?(pid)
  end

  test "read response body in chunks with reused connection and closing it" do
    uri = URI.parse(@http)
    {:ok, conn} = :gun.open(to_charlist(uri.host), uri.port)

    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} = call(request, body_as: :chunks, conn: conn)
    assert response.status == 200
    %{pid: pid, stream: stream, opts: opts} = response.body
    assert opts[:body_as] == :chunks
    assert is_pid(pid)
    assert is_reference(stream)

    assert read_body(pid, stream, "", false) |> byte_size() == 16
    assert Process.alive?(pid)

    # reusing connection
    assert {:ok, %Env{} = response} = call(request, body_as: :chunks, conn: conn)
    assert response.status == 200
    %{pid: pid, stream: stream, opts: opts} = response.body
    assert opts[:body_as] == :chunks
    assert is_pid(pid)
    assert is_reference(stream)

    assert read_body(pid, stream, "", false) |> byte_size() == 16
    assert Process.alive?(pid)

    :ok = Gun.close(pid)
    refute Process.alive?(pid)
  end

  test "read response body in stream" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} = call(request, body_as: :stream)
    assert response.status == 200
    assert is_function(response.body)
    assert Enum.to_list(response.body) |> List.to_string() |> byte_size() == 16
  end

  test "read response body in stream with opened connection without closing connection" do
    uri = URI.parse(@http)
    {:ok, conn} = :gun.open(to_charlist(uri.host), uri.port)

    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} =
             call(request, body_as: :stream, conn: conn, close_conn: false)

    assert response.status == 200
    assert is_function(response.body)
    assert Enum.to_list(response.body) |> List.to_string() |> byte_size() == 16

    assert Process.alive?(conn)

    :ok = Gun.close(conn)
    refute Process.alive?(conn)
  end

  test "read response body in stream with opened connection with closing connection" do
    uri = URI.parse(@http)
    {:ok, conn} = :gun.open(to_charlist(uri.host), uri.port)

    request = %Env{
      method: :get,
      url: "#{@http}/stream-bytes/10"
    }

    assert {:ok, %Env{} = response} = call(request, body_as: :stream, conn: conn)

    assert response.status == 200
    assert is_function(response.body)
    assert Enum.to_list(response.body) |> List.to_string() |> byte_size() == 16

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

  test "query without path" do
    request = %Env{
      method: :get,
      url: "#{@http}",
      query: [
        param: "value"
      ]
    }

    assert {:ok, %Env{} = response} = call(request, timeout: 1_000)
    assert response.status == 400
  end

  defp read_body(pid, stream, acc \\ "", close_conn \\ true) do
    case Gun.read_chunk(pid, stream, timeout: 1_000) do
      {:fin, body} ->
        if close_conn do
          :ok = Gun.close(pid)
        end

        acc <> body

      {:nofin, part} ->
        read_body(pid, stream, acc <> part, close_conn)
    end
  end
end
