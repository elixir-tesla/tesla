defmodule Tesla.Middleware.QueryTest do
  use ExUnit.Case
  alias Tesla.Env

  @middleware Tesla.Middleware.Query

  test "joining default query params" do
    assert {:ok, env} = @middleware.call(%Env{}, [], page: 1)
    assert env.query == [page: 1]
  end

  test "should not override existing key" do
    assert {:ok, env} = @middleware.call(%Env{query: [page: 1]}, [], page: 5)
    assert env.query == [page: 1, page: 5]
  end
end
