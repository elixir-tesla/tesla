defmodule Tesla.Middleware.QueryTest do
  use ExUnit.Case
  alias Tesla.Env

  @middleware Tesla.Middleware.Query

  test "joining default query params" do
    assert {:ok, env} = @middleware.call(%Env{}, [], page: 1)
    assert env.query == [page: 1]
  end

  test "ignores nil default query params" do
    assert {:ok, env} = @middleware.call(%Env{query: [page: 1]}, [], nil)
    assert env.query == [page: 1]
  end

  test "should not override existing key" do
    assert {:ok, env} = @middleware.call(%Env{query: [page: 1]}, [], page: 5)
    assert env.query == [page: 1, page: 5]
  end

  test "merges query maps without overriding existing keys" do
    assert {:ok, env} =
             @middleware.call(%Env{query: %{page: 1, filters: %{name: "foo"}}}, [], %{
               page: 5,
               per_page: 10
             })

    assert env.query == %{page: 1, per_page: 10, filters: %{name: "foo"}}
  end

  test "merges existing map query with list defaults without crashing" do
    assert {:ok, env} = @middleware.call(%Env{query: %{page: 1}}, [], per_page: 10)
    assert env.query == [page: 1, per_page: 10]
  end

  test "merges map query with list defaults without losing params" do
    assert {:ok, env} =
             @middleware.call(%Env{url: "http://example.com", query: %{b: 2, a: 1}}, [], c: 3)

    assert URI.decode_query(Tesla.build_url(env) |> URI.parse() |> Map.fetch!(:query)) ==
             %{"a" => "1", "b" => "2", "c" => "3"}
  end

  test "merges existing list query with map defaults without crashing" do
    assert {:ok, env} = @middleware.call(%Env{query: [page: 1]}, [], %{per_page: 10})
    assert env.query == [page: 1, per_page: 10]
  end
end
