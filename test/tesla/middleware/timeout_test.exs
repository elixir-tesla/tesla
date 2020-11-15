defmodule Tesla.Middleware.TimeoutTest do
  use ExUnit.Case, async: false

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Timeout, timeout: 100

    adapter fn env ->
      case env.url do
        "/sleep_50ms" ->
          Process.sleep(50)
          {:ok, %{env | status: 200}}

        "/sleep_150ms" ->
          Process.sleep(150)
          {:ok, %{env | status: 200}}

        "/error" ->
          {:error, :adapter_error}

        "/raise" ->
          raise "custom_exception"

        "/throw" ->
          throw(:throw_value)

        "/exit" ->
          exit(:exit_value)
      end
    end
  end

  defmodule DefaultTimeoutClient do
    use Tesla

    plug Tesla.Middleware.Timeout

    adapter fn env ->
      case env.url do
        "/sleep_950ms" ->
          Process.sleep(950)
          {:ok, %{env | status: 200}}

        "/sleep_1050ms" ->
          Process.sleep(1_050)
          {:ok, %{env | status: 200}}
      end
    end
  end

  describe "using custom timeout (100ms)" do
    test "should return timeout error when the stack timeout" do
      assert {:error, :timeout} = Client.get("/sleep_150ms")
    end

    test "should return the response when not timeout" do
      assert {:ok, %Tesla.Env{status: 200}} = Client.get("/sleep_50ms")
    end

    test "should not kill calling process" do
      Process.flag(:trap_exit, true)

      pid =
        spawn_link(fn ->
          assert {:error, :timeout} = Client.get("/sleep_150ms")
        end)

      assert_receive {:EXIT, ^pid, :normal}, 200
    end
  end

  describe "using default timeout (1_000ms)" do
    test "should raise a Tesla.Error when the stack timeout" do
      assert {:error, :timeout} = DefaultTimeoutClient.get("/sleep_1050ms")
    end

    test "should return the response when not timeout" do
      assert {:ok, %Tesla.Env{status: 200}} = DefaultTimeoutClient.get("/sleep_950ms")
    end
  end

  describe "repassing errors and exit" do
    test "should repass rescued errors" do
      assert_raise RuntimeError, "custom_exception", fn ->
        Client.get("/raise")
      end
    end

    test "should keep original stacktrace information" do
      try do
        Client.get("/raise")
      rescue
        _ in RuntimeError ->
          [{last_module, _, _, file_info} | _] = __STACKTRACE__

          assert Tesla.Middleware.TimeoutTest.Client == last_module
          assert [file: 'lib/tesla/builder.ex', line: 23] == file_info
      else
        _ ->
          flunk("Expected exception to be thrown")
      end
    end

    test "should add timeout module info to stacktrace" do
      try do
        Client.get("/raise")
      rescue
        _ in RuntimeError ->
          [_, {timeout_module, _, _, module_file_info} | _] = __STACKTRACE__

          assert Tesla.Middleware.Timeout == timeout_module
          assert module_file_info == [file: 'lib/tesla/middleware/timeout.ex', line: 45]
      else
        _ ->
          flunk("Expected exception to be thrown")
      end
    end

    test "should repass thrown value" do
      assert catch_throw(Client.get("/throw")) == :throw_value
    end

    test "should repass exit value" do
      assert catch_exit(Client.get("/exit")) == :exit_value
    end
  end
end
