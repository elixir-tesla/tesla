defmodule LoggerTest do
  use ExUnit.Case, async: false

  use Tesla.Middleware.TestCase, middleware: Tesla.Middleware.Logger
  use Tesla.Middleware.TestCase, middleware: Tesla.Middleware.DebugLogger

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
        "/ok_json"          -> {200, "{\"message\": \"ok\""}
      end
      %{env | status: status, body: body}
    end
  end

  defmodule JSONClient do
    use Tesla

    plug Tesla.Middleware.Logger
    plug Tesla.Middleware.DebugLogger
    plug Tesla.Middleware.JSON

    adapter fn (env) ->
      {status, body} = case env.url do
        "/ok_json"          -> {200, ~s<{"status": "ok"}>}
      end
      %{env | status: status, body: body, headers: %{"content-type" => "application/json"}}
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

  test "ok with json" do
    log = capture_log(fn -> JSONClient.get("/ok_json") end)
    assert log =~ "status"
    assert log =~ "ok"    
  end
end
