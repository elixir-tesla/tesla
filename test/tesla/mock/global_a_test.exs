defmodule Tesla.Mock.GlobalATest do
  use ExUnit.Case, async: false

  setup_all do
    Tesla.Mock.mock_global(fn _env -> %Tesla.Env{status: 200, body: "AAA"} end)

    :ok
  end

  test "mock get request" do
    assert {:ok, %Tesla.Env{} = env} = MockClient.get("/")
    assert env.body == "AAA"
  end
end
