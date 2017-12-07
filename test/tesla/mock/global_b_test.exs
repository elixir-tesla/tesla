defmodule Tesla.Mock.GlobalBTest do
  use ExUnit.Case, async: false

  setup_all do
    Tesla.Mock.mock_global fn
      _env -> %Tesla.Env{status: 200, body: "BBB"}
    end

    :ok
  end

  test "mock get request" do
    assert %Tesla.Env{} = env = MockClient.get("/")
    assert env.body == "BBB"
  end
end
