defmodule Tesla.Adapter.FinchTest do
  use ExUnit.Case

  @finch_name MyFinch

  use Tesla.AdapterCase, adapter: {Tesla.Adapter.Finch, [name: @finch_name]}
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.StreamResponseBody
  use Tesla.AdapterCase.SSL
  use Tesla.AdapterCase.Query

  setup do
    opts = [
      name: @finch_name,
      pools: %{
        @https => [
          conn_opts: [
            transport_opts: [cacertfile: "#{:code.priv_dir(:httparrot)}/ssl/server-ca.crt"]
          ]
        ]
      }
    ]

    start_supervised!({Finch, opts})
    :ok
  end

  test "Delay request" do
    request = %Env{
      method: :head,
      url: "#{@http}/delay/1"
    }

    assert {:error, :timeout} = call(request, receive_timeout: 100)
  end

  test "Delay request with stream" do
    request = %Env{
      method: :head,
      url: "#{@http}/delay/1"
    }

    assert {:error, :timeout} = call(request, receive_timeout: 100, response: :stream)
  end

  test "Stream request handles errors without raising CaseClauseError" do
    # This test verifies that streaming errors (like proxy 403) are properly
    # handled in the callback and receive blocks instead of raising CaseClauseError.
    # Before the fix, an error during streaming would cause:
    #   (CaseClauseError) no case clause matching: {:error, error, nil}

    assert {:error, _} =
             Tesla.Adapter.Finch.call(
               %Tesla.Env{
                 method: :get,
                 url: "http://nonexistent.invalid",
                 body: nil,
                 headers: []
               },
               name: @finch_name,
               response: :stream,
               receive_timeout: 1000
             )
  end

  test "raises on an unknown :response option" do
    assert_raise RuntimeError, ~r/Unknown response option: :bogus/, fn ->
      call(%Env{method: :get, url: "#{@http}/ip"}, response: :bogus)
    end
  end

  describe "streamed response failures" do
    test "raises with the transport reason when the connection drops mid stream" do
      url = start_chunked_server(fn socket -> :gen_tcp.close(socket) end)

      assert {:ok, env} =
               call(%Env{method: :get, url: url}, response: :stream, receive_timeout: 200)

      assert_raise Tesla.Error, ~r/^:closed /, fn -> Enum.to_list(env.body) end
    end

    test "raises with :timeout when the next chunk takes longer than :receive_timeout" do
      url = start_chunked_server(fn _socket -> Process.sleep(1_000) end)

      assert {:ok, env} =
               call(%Env{method: :get, url: url}, response: :stream, receive_timeout: 200)

      assert_raise Tesla.Error, ~r/^:timeout /, fn -> Enum.to_list(env.body) end
    end

    test "ends the stream without raising when the response carries trailers" do
      url =
        start_chunked_server(fn socket ->
          :gen_tcp.send(socket, "0\r\nx-checksum: abc123\r\n\r\n")
        end)

      assert {:ok, env} =
               call(%Env{method: :get, url: url}, response: :stream, receive_timeout: 200)

      assert Enum.to_list(env.body) == ["hello"]
    end

    test "ends the stream without raising when the response completes" do
      url = start_chunked_server(fn socket -> :gen_tcp.send(socket, "0\r\n\r\n") end)

      assert {:ok, env} =
               call(%Env{method: :get, url: url}, response: :stream, receive_timeout: 200)

      assert Enum.to_list(env.body) == ["hello"]
    end
  end

  # Sends a chunked response with a single "hello" chunk, then hands the socket
  # over to `after_chunk` to decide how the response ends.
  defp start_chunked_server(after_chunk) do
    {:ok, listen} =
      :gen_tcp.listen(0,
        ip: {127, 0, 0, 1},
        mode: :binary,
        packet: :raw,
        active: false,
        reuseaddr: true
      )

    {:ok, port} = :inet.port(listen)

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen, 5_000)
      {:ok, _request} = :gen_tcp.recv(socket, 0, 5_000)

      :gen_tcp.send(socket, [
        "HTTP/1.1 200 OK\r\n",
        "content-type: text/event-stream\r\n",
        "transfer-encoding: chunked\r\n\r\n",
        "5\r\nhello\r\n"
      ])

      after_chunk.(socket)
      # Keep the socket owner alive so the last bytes are not lost on exit.
      Process.sleep(500)
    end)

    "http://127.0.0.1:#{port}/"
  end
end
