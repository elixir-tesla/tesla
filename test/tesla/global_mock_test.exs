defmodule Tesla.GlobalMockTest do
  use ExUnit.Case, async: false

  setup_all do
    Tesla.Mock.mock_global(fn
      %{method: :get, url: "/list", __pid__: pid} ->
        %Tesla.Env{status: 200, body: "hello", __pid__: pid}

      %{method: :post, url: "/create"} ->
        {201, %{}, %{id: 42}}
    end)

    :ok
  end

  test "mock request from spawned process" do
    pid = self()
    spawn(fn -> send(pid, MockClient.get("/list")) end)

    assert_receive {:ok, %Tesla.Env{status: 200, body: "hello"}}
  end

  test "__pid__ is passed correctly" do
    pid = self()
    child_pid = spawn(fn -> send(pid, MockClient.get("/list")) end)

    assert_receive {:ok, %Tesla.Env{status: 200, body: "hello", __pid__: child_pid}}
  end
end
