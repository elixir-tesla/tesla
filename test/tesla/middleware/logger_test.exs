defmodule Tesla.Middleware.LoggerTest do
  use ExUnit.Case, async: false

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Logger
    plug Tesla.Middleware.DebugLogger

    adapter fn (env) ->
      {status, body} = case env.url do
        "/connection-error" -> raise %Tesla.Error{message: "adapter error: :econnrefused", reason: :econnrefused}
        "/server-error"     -> {500, "error"}
        "/client-error"     -> {404, "error"}
        "/redirect"         -> {301, "moved"}
        "/ok"               -> {200, "ok"}
      end
      %{env | status: status, headers: %{"content-type" => "text/plain"}, body: body}
    end
  end

  import ExUnit.CaptureLog

  test "connection error" do
    log = capture_log(fn ->
      assert_raise Tesla.Error, fn -> Client.get("/connection-error") end
    end)
    assert log =~ "/connection-error -> adapter error: :econnrefused"
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

  test "multipart" do
    mp = Tesla.Multipart.new() |> Tesla.Multipart.add_field("field1", "foo")
    log = capture_log(fn -> Client.post("/ok", mp) end)
    assert log =~ "boundary: #{mp.boundary}"
    assert log =~ inspect List.first(mp.parts)
  end

  test "stream" do
    stream = Stream.map((1..10), fn i -> "chunk: #{i}" end)
    log = capture_log(fn -> Client.post("/ok", stream) end)
    assert log =~ "/ok -> 200"
  end
end
