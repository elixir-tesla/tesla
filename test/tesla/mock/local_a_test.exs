defmodule Tesla.Mock.LocalATest do
  use ExUnit.Case, async: true

  setup do
    Tesla.Mock.mock(fn _env -> %Tesla.Env{status: 200, body: "AAA"} end)

    :ok
  end

  test "mock get request" do
    assert {:ok, %Tesla.Env{} = env} = MockClient.get("/")
    assert env.body == "AAA"
  end
end
