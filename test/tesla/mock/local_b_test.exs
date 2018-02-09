defmodule Tesla.Mock.LocalBTest do
  use ExUnit.Case, async: true

  setup do
    Tesla.Mock.mock(fn _env -> %Tesla.Env{status: 200, body: "BBB"} end)

    :ok
  end

  test "mock get request" do
    assert {:ok, %Tesla.Env{} = env} = MockClient.get("/")
    assert env.body == "BBB"
  end
end
