defmodule Tesla.Middleware.BearerAuthTest do
  use ExUnit.Case
  alias Tesla.Env

  @middleware Tesla.Middleware.BearerAuth

  test "adds expected headers" do
    assert {:ok, env} = @middleware.call(%Env{}, [], [])
    assert env.headers == [{"authorization", "Bearer "}]

    assert {:ok, env} = @middleware.call(%Env{}, [], token: "token")
    assert env.headers == [{"authorization", "Bearer token"}]
  end
end
