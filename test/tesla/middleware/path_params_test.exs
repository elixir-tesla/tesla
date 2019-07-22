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

  test "value is not given" do
    opts = [path_params: [y: 42]]
    assert {:ok, env} = @middleware.call(%Env{url: "/users/:x", opts: opts}, [], nil)
    assert env.url == "/users/:x"
  end

  test "value is nil" do
    opts = [path_params: [id: nil]]
    assert {:ok, env} = @middleware.call(%Env{url: "/users/:id", opts: opts}, [], nil)
    assert env.url == "/users/:id"
  end

  test "placeholder contains another placeholder" do
    opts = [path_params: [id: 1, id_post: 2]]

    assert {:ok, env} = @middleware.call(%Env{url: "/users/:id/p/:id_post", opts: opts}, [], nil)

    assert env.url == "/users/1/p/2"
  end
end
