defmodule Tesla.Mock.GlobalReplaceTest do
  use ExUnit.Case, async: false

  test "a later global mock replaces the one already running" do
    Tesla.Mock.mock_global(fn _env -> %Tesla.Env{status: 200, body: "first"} end)

    assert {:ok, %Tesla.Env{} = env} = MockClient.get("/")
    assert env.body == "first"

    Tesla.Mock.mock_global(fn _env -> %Tesla.Env{status: 200, body: "second"} end)

    assert {:ok, %Tesla.Env{} = env} = MockClient.get("/")
    assert env.body == "second"
  end
end
