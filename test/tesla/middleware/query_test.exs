defmodule Tesla.Middleware.QueryTest do
  use ExUnit.Case
  alias Tesla.Env
  alias Tesla.QueryString
  alias Tesla.QueryStringError

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

  test "uses query string defaults when request query is empty" do
    query_string = QueryString.raw!("foo=a+%2B+b&bar=true")

    assert {:ok, env} = @middleware.call(%Env{query: []}, [], query_string)
    assert env.query == query_string
  end

  test "uses query string defaults when request query is nil" do
    query_string = QueryString.raw!("foo=a+%2B+b&bar=true")

    assert {:ok, env} = @middleware.call(%Env{query: nil}, [], query_string)
    assert env.query == query_string
  end

  test "keeps existing query string when defaults are empty" do
    query_string = QueryString.raw!("foo=a+%2B+b&bar=true")

    assert {:ok, env} = @middleware.call(%Env{query: query_string}, [], [])
    assert env.query == query_string
  end

  test "rejects merging existing query string with normal defaults" do
    query_string = QueryString.raw!("foo=a+%2B+b&bar=true")

    assert_raise QueryStringError,
                 ~r/cannot merge Tesla.QueryString with normal query params/,
                 fn ->
                   @middleware.call(%Env{query: query_string}, [], page: 1)
                 end
  end

  test "rejects merging normal request query with query string defaults" do
    query_string = QueryString.raw!("foo=a+%2B+b&bar=true")

    assert_raise QueryStringError,
                 ~r/cannot merge Tesla.QueryString with normal query params/,
                 fn ->
                   @middleware.call(%Env{query: [page: 1]}, [], query_string)
                 end
  end
end
