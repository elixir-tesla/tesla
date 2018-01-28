defmodule Tesla.Middleware.HeadersTest do
  use ExUnit.Case
  alias Tesla.Env

  @middleware Tesla.Middleware.Headers

  test "merge headers" do
    env =
      @middleware.call(%Env{headers: [{"authorization", "secret"}]}, [], [
        {"content-type", "text/plain"}
      ])

    assert env.headers == [{"authorization", "secret"}, {"content-type", "text/plain"}]
  end
end
