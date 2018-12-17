defmodule Tesla.Middleware.PathParamsTest do
  use ExUnit.Case, async: true
  alias Tesla.Env

  @middleware Tesla.Middleware.PathParams

  test "no params" do
    assert {:ok, env} = @middleware.call(%Env{url: "/users/:id"}, [], nil)
    assert env.url == "/users/:id"
  end

  test "passed params" do
    opts = [path_params: [id: 42]]
    assert {:ok, env} = @middleware.call(%Env{url: "/users/:id", opts: opts}, [], nil)
    assert env.url == "/users/42"
  end
end
