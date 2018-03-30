defmodule Tesla.GlobalMockTest do
  use ExUnit.Case, async: false

  setup_all do
    Tesla.Mock.mock_global(fn
      %{method: :get, url: "/list"} -> %Tesla.Env{status: 200, body: "hello"}
      %{method: :post, url: "/create"} -> {201, %{}, %{id: 42}}
    end)

    :ok
  end

  test "mock request from spawned process" do
    pid = self()
    spawn(fn -> send(pid, MockClient.get("/list")) end)

    assert_receive {:ok, %Tesla.Env{status: 200, body: "hello"}}
  end
end
