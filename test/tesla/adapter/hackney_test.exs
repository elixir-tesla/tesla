defmodule Tesla.Adapter.HackneyTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Hackney
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.Query

  use Tesla.AdapterCase.SSL,
    ssl_options: [
      verify: :verify_peer,
      cacertfile: Path.join([to_string(:code.priv_dir(:httparrot)), "/ssl/server-ca.crt"])
    ]

  alias Tesla.Env

  test "get with `with_body: true` option" do
    request = %Env{
      method: :get,
      url: "#{@http}/ip"
    }

    assert {:ok, %Env{} = response} = call(request, with_body: true)

    assert response.status == 200
  end

  test "get with `with_body: true` option even when async" do
    request = %Env{
      method: :get,
      url: "#{@http}/ip"
    }

    assert {:ok, %Env{} = response} = call(request, with_body: true, async: true)
    assert response.status == 200
    assert is_reference(response.body) or is_pid(response.body)
  end

  @hackney_version :hackney |> Application.spec(:vsn) |> to_string()

  if Version.compare(@hackney_version, "4.0.0") == :lt do
    test "get with `:max_body` option" do
      body = String.duplicate("long response", 1000)

      request = %Env{
        method: :post,
        url: "#{@http}/post",
        body: body
      }

      assert {:ok, %Env{} = full_response} = call(request, with_body: true)
      assert {:ok, %Env{} = limited_response} = call(request, with_body: true, max_body: 100)
      assert full_response.status == 200
      assert limited_response.status == 200
      assert byte_size(limited_response.body) < byte_size(full_response.body)
    end
  end

  test "request timeout error" do
    request = %Env{
      method: :get,
      url: "#{@http}/delay/10",
      body: "test"
    }

    assert {:error, :timeout} = call(request, recv_timeout: 100)
  end

  test "stream request body: error" do
    body =
      Stream.unfold(5, fn
        0 -> nil
        3 -> {fn -> {:error, :fake_error} end, 2}
        n -> {to_string(n), n - 1}
      end)

    request = %Env{
      method: :post,
      url: "#{@http}/post",
      body: body
    }

    assert {:error, :fake_error} = call(request)
  end

  describe "streamed request bodies" do
    test "surfaces the error hackney reported when opening the request" do
      request = %Env{
        method: :post,
        url: "http://localhost:1/post",
        headers: [{"content-type", "text/plain"}],
        body: Stream.map(["ab"], & &1)
      }

      assert {:error, :econnrefused} = call(request)
    end

    test "stops reading the response body once `:max_body` is reached" do
      request = streamed_post(String.duplicate("long response", 1000))

      assert {:ok, %Env{} = full_response} = call(request)
      assert {:ok, %Env{} = limited_response} = call(request, max_body: 100)

      assert full_response.status == 200
      assert limited_response.status == 200
      assert byte_size(limited_response.body) < byte_size(full_response.body)
    end

    test "reads the whole response body when it stays under `:max_body`" do
      request = streamed_post(String.duplicate("long response", 1000))

      assert {:ok, %Env{} = full_response} = call(request)
      assert {:ok, %Env{} = limited_response} = call(request, max_body: 1_000_000)

      assert limited_response.body == full_response.body
    end

    test "surfaces the error hackney reported while reading the response body" do
      url = start_stalled_chunked_server()

      request = %Env{
        method: :post,
        url: url,
        headers: [{"content-type", "text/plain"}],
        body: Stream.map(["ab"], & &1)
      }

      assert {:error, :timeout} = call(request, max_body: 1_000_000, recv_timeout: 100)
    end
  end

  defp streamed_post(body) do
    %Env{
      method: :post,
      url: "#{@http}/post",
      headers: [{"content-type", "text/plain"}],
      body: Stream.map([body], & &1)
    }
  end

  # Answers with a chunked response that stops after the first chunk without
  # ever ending, so reading the body stalls part way through.
  defp start_stalled_chunked_server do
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
        "transfer-encoding: chunked\r\n\r\n",
        "5\r\nhello\r\n"
      ])

      Process.sleep(5_000)
    end)

    "http://127.0.0.1:#{port}/"
  end
end
