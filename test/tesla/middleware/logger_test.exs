defmodule Tesla.Middleware.LoggerTest do
  use ExUnit.Case, async: false

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Logger
    plug Tesla.Middleware.DebugLogger

    adapter fn env ->
      env = Tesla.put_header(env, "content-type", "text/plain")

      case env.url do
        "/connection-error" ->
          {:error, :econnrefused}

        "/server-error" ->
          {:ok, %{env | status: 500, body: "error"}}

        "/client-error" ->
          {:ok, %{env | status: 404, body: "error"}}

        "/redirect" ->
          {:ok, %{env | status: 301, body: "moved"}}

        "/ok" ->
          {:ok, %{env | status: 200, body: "ok"}}
      end
    end
  end

  import ExUnit.CaptureLog

  test "connection error" do
    log =
      capture_log(fn ->
        assert {:error, _} = Client.get("/connection-error")
      end)

    assert log =~ "/connection-error -> :econnrefused"
  end

  test "server error" do
    log = capture_log(fn -> Client.get("/server-error") end)
    assert log =~ "/server-error -> 500"
  end

  test "client error" do
    log = capture_log(fn -> Client.get("/client-error") end)
    assert log =~ "/client-error -> 404"
  end

  test "redirect" do
    log = capture_log(fn -> Client.get("/redirect") end)
    assert log =~ "/redirect -> 301"
  end

  test "ok" do
    log = capture_log(fn -> Client.get("/ok") end)
    assert log =~ "/ok -> 200"
  end

  test "ok with params" do
    log = capture_log(fn -> Client.get("/ok", query: %{"test" => "true"}) end)
    assert log =~ "Query Param 'test': 'true'"
  end

  test "ok with list params" do
    log = capture_log(fn -> Client.get("/ok", query: %{"test" => ["first", "second"]}) end)
    assert log =~ "Query Param 'test[]': 'first'"
    assert log =~ "Query Param 'test[]': 'second'"
  end

  test "multipart" do
    mp = Tesla.Multipart.new() |> Tesla.Multipart.add_field("field1", "foo")
    log = capture_log(fn -> Client.post("/ok", mp) end)
    assert log =~ "boundary: #{mp.boundary}"
    assert log =~ inspect(List.first(mp.parts))
  end

  test "stream" do
    stream = Stream.map(1..10, fn i -> "chunk: #{i}" end)
    log = capture_log(fn -> Client.post("/ok", stream) end)
    assert log =~ "/ok -> 200"
  end
end
