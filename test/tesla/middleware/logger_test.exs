defmodule LoggerTest do
  use ExUnit.Case

  setup do
    Tesla.Adapter.Ibrowse.start
    {:ok, %{}}
  end

  defmodule Client do
    use Tesla.Builder

    with Tesla.Middleware.Headers, %{'Content-Type' => 'text/plain'}
    with Tesla.Middleware.Logger
    with Tesla.Middleware.DebugLogger

    adapter fn (env) ->
      case env.url do
        "/server-error" -> {500, %{"Content-Type": "text/plain"}, "error"}
        "/client-error" -> {404, %{"Content-Type": "text/plain"}, "error"}
        "/redirect"     -> {301, %{"Content-Type": "text/plain"}, "moved"}
        "/ok"           -> {200, %{"Content-Type": "text/plain"}, "ok"}
      end
    end
  end

  test "server error" do
    Client.get("/server-error")
  end

  test "client error" do
    Client.get("/client-error")
  end

  test "redirect" do
    Client.get("/redirect")
  end

  test "ok" do
    Client.get("/ok")
  end
end
