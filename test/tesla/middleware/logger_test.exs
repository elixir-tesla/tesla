defmodule LoggerTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla.Builder

    plug Tesla.Middleware.Headers, %{'Content-Type' => 'text/plain'}
    plug Tesla.Middleware.Logger
    plug Tesla.Middleware.DebugLogger

    adapter fn (env) ->
      case env.url do
        "/server-error" -> {500, %{"Content-Type": "text/plain"}, "error"}
        "/client-error" -> {404, %{"Content-Type": "text/plain"}, "error"}
        "/redirect"     -> {301, %{"Content-Type": "text/plain"}, "moved"}
        "/ok"           -> {200, %{"Content-Type": "text/plain"}, "ok"}
      end
    end
  end

  import ExUnit.CaptureLog

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
end
