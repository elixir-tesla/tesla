defmodule Tesla.Adapter.MintTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Mint
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody

  use Tesla.AdapterCase.SSL,
    transport_opts: [
      cacertfile: Path.join([to_string(:code.priv_dir(:httparrot)), "/ssl/server-ca.crt"])
    ]

  test "Delay request" do
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

  describe "reusing connection" do
    setup do
      uri = URI.parse(@http)
      {:ok, conn} = Mint.HTTP.connect(:http, uri.host, uri.port)
      {:ok, conn: conn, original: "#{uri.host}:#{uri.port}"}
    end

    test "body_as :plain", %{conn: conn, original: original} do
      request = %Env{
        method: :get,
        url: "#{@http}/stream-bytes/10"
      }

      assert {:ok, %Env{} = response} =
               call(request, conn: conn, original: original, close_conn: false)

      assert response.status == 200
      assert byte_size(response.body) == 16

      assert {:ok, %Env{} = response} =
               call(request, conn: conn, original: original, close_conn: false)

      assert response.status == 200
      assert byte_size(response.body) == 16

      assert {:ok, conn} = Tesla.Adapter.Mint.close(conn)
      assert conn.state == :closed
    end

    test "body_as :stream", %{conn: conn, original: original} do
      request = %Env{
        method: :get,
        url: "#{@http}/stream-bytes/10"
      }

      assert {:ok, %Env{} = response} =
               call(request,
                 conn: conn,
                 original: original,
                 close_conn: false,
                 body_as: :stream
               )

      assert response.status == 200
      assert is_function(response.body)
      assert Enum.join(response.body) |> byte_size() == 16

      assert {:ok, %Env{} = response} =
               call(request,
                 conn: conn,
                 original: original,
                 close_conn: false,
                 body_as: :stream
               )

      assert response.status == 200
      assert is_function(response.body)
      assert Enum.join(response.body) |> byte_size() == 16

      assert {:ok, conn} = Tesla.Adapter.Mint.close(conn)
      assert conn.state == :closed
    end

    test "body_as :chunks", %{conn: conn, original: original} do
      request = %Env{
        method: :get,
        url: "#{@http}/stream-bytes/10"
      }

      assert {:ok, %Env{} = response} =
               call(request,
                 conn: conn,
                 original: original,
                 close_conn: false,
                 body_as: :chunks
               )

      assert response.status == 200
      assert %{conn: received_conn, ref: ref, opts: opts, body: body} = response.body
      {:ok, conn, received_body} = read_body(received_conn, ref, opts, body)
      assert byte_size(received_body) == 16
      assert conn.socket == received_conn.socket

      assert {:ok, %Env{} = response} =
               call(request,
                 conn: conn,
                 original: original,
                 close_conn: false,
                 body_as: :chunks
               )

      assert response.status == 200
      assert %{conn: received_conn, ref: ref, opts: opts, body: body} = response.body
      {:ok, conn, received_body} = read_body(received_conn, ref, opts, body)
      assert byte_size(received_body) == 16
      assert conn.socket == received_conn.socket

      {:ok, conn} = Tesla.Adapter.Mint.close(received_conn)
      assert conn.state == :closed
    end

    test "don't reuse connection if original does not match", %{conn: conn} do
      request = %Env{
        method: :get,
        url: "#{@http}/stream-bytes/10"
      }

      assert {:ok, %Env{} = response} =
               call(request, body_as: :chunks, conn: conn, original: "example.com:80")

      assert response.status == 200
      %{conn: received_conn, ref: ref, opts: opts, body: body} = response.body

      {:ok, received_conn, received_body} = read_body(received_conn, ref, opts, body)
      assert byte_size(received_body) == 16
      refute conn.socket == received_conn.socket
      refute opts[:conn]
      assert opts[:old_conn].socket == conn.socket
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
end
