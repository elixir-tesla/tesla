defmodule Tesla.Middleware.APIKeyAuthTest do
  use ExUnit.Case

  alias Tesla.Middleware.APIKeyAuth

  describe "raises when" do
    test "`add_to` is not provided" do
      assert_raise KeyError, fn ->
        APIKeyAuth.call(%Tesla.Env{}, [], [])
      end
    end

    test "`add_to is not :header or :query" do
      assert_raise CaseClauseError, fn ->
        APIKeyAuth.call(%Tesla.Env{}, [], [add_to: :cookie])
      end
    end
  end

  describe "adds expected" do
    test "header when `add_to` is :header" do
      assert {:ok, env} = APIKeyAuth.call(%Tesla.Env{}, [], [add_to: :header])
      assert env.headers == [{"", ""}]

      opts = [name: "X-API-KEY", value: "apikey", add_to: :header]
      assert {:ok, env} = APIKeyAuth.call(%Tesla.Env{}, [], opts)
      assert env.headers == [{"X-API-KEY", "apikey"}]
    end

    test "query param when `add_to` is :query" do
      assert {:ok, env} = APIKeyAuth.call(%Tesla.Env{}, [], [add_to: :query])
      assert env.query == [{"", ""}]

      opts = [name: "key", value: "apikey", add_to: :query]
      assert {:ok, env} = APIKeyAuth.call(%Tesla.Env{}, [], opts)
      assert env.query == [{"key", "apikey"}]
    end
  end
end
