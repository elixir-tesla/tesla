defmodule Tesla.Mock.MultiprocessLocalTest do
  use ExUnit.Case, async: true

  setup do
    Tesla.Mock.mock(fn _env -> %Tesla.Env{status: 200, body: "hello"} end)

    :ok
  end

  test "success case" do
    task = Task.async(fn ->
      assert {:ok, %Tesla.Env{} = env} = MockClient.get("/")
      assert env.body == "hello"
    end)

    Task.await(task)
  end

  test "when the mock adapter can't be found, it raises an error with a helpful message" do

    test_pid = self()

    # Starting the parent with raw spawn, then killing the parent, will
    # mean that ProcessTree.get() can't find the mock adapter in the process
    # dictionary of the test pid, which is what we want to happen for this test.
    spawn(fn ->
      parent = self()

      Task.async(fn ->
        Process.exit(parent, :kill)

        try do
          assert_raise Tesla.Mock.Error, ~r/not compatible with local mocking/, fn ->
            MockClient.get("/")
          end
          send(test_pid, :ok)
        rescue
          e -> send(test_pid, {:error, e, __STACKTRACE__})
        end
      end)
    end)

    receive do
      :ok ->
        :ok

      {:error, e, stack_trace} ->
        reraise e, stack_trace
    end
  end
end
