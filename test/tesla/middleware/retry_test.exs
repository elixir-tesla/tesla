defmodule Tesla.Middleware.RetryTest do
  use ExUnit.Case, async: false

  defmodule LaggyAdapter do
    def start_link, do: Agent.start_link(fn -> 0 end, name: __MODULE__)

    def call(env, _opts) do
      Agent.get_and_update(__MODULE__, fn retries ->
        response =
          case env.url do
            "/ok" -> {:ok, env}
            "/maybe" when retries < 5 -> {:error, :econnrefused}
            "/maybe" -> {:ok, env}
            "/nope" -> {:error, :econnrefused}
            "/retry_status" when retries < 5 -> {:ok, %{env | status: 500}}
            "/retry_status" -> {:ok, %{env | status: 200}}
          end

        {response, retries + 1}
      end)
    end
  end

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Retry,
      delay: 10,
      max_retries: 10,
      jitter_factor: 0.25

    adapter LaggyAdapter
  end

  defmodule ClientWithShouldRetryFunction do
    use Tesla

    plug Tesla.Middleware.Retry,
      delay: 10,
      max_retries: 10,
      should_retry: fn
        {:ok, %{status: status}} when status in [400, 500] -> true
        {:ok, _} -> false
        {:error, _} -> true
      end

    adapter LaggyAdapter
  end

  setup do
    {:ok, _} = LaggyAdapter.start_link()
    :ok
  end

  test "pass on successful request" do
    assert {:ok, %Tesla.Env{url: "/ok", method: :get}} = Client.get("/ok")
  end

  test "finally pass on laggy request" do
    assert {:ok, %Tesla.Env{url: "/maybe", method: :get}} = Client.get("/maybe")
  end

  test "raise if max_retries is exceeded" do
    assert {:error, :econnrefused} = Client.get("/nope")
  end

  test "use default retry determination function" do
    assert {:ok, %Tesla.Env{url: "/retry_status", method: :get, status: 500}} =
             Client.get("/retry_status")
  end

  test "use custom retry determination function" do
    assert {:ok, %Tesla.Env{url: "/retry_status", method: :get, status: 200}} =
             ClientWithShouldRetryFunction.get("/retry_status")
  end

  defmodule DefunctClient do
    use Tesla

    plug Tesla.Middleware.Retry

    adapter fn _ -> raise "runtime-error" end
  end

  test "raise in case or unexpected error" do
    assert_raise RuntimeError, fn -> DefunctClient.get("/blow") end
  end

  test "ensures delay option is positive" do
    defmodule ClientWithZeroDelay do
      use Tesla
      plug Tesla.Middleware.Retry, delay: 0
      adapter LaggyAdapter
    end

    assert_raise ArgumentError, "expected :delay to be an integer >= 1, got 0", fn ->
      ClientWithZeroDelay.get("/ok")
    end
  end

  test "ensures delay option is an integer" do
    defmodule ClientWithFloatDelay do
      use Tesla
      plug Tesla.Middleware.Retry, delay: 0.25
      adapter LaggyAdapter
    end

    assert_raise ArgumentError, "expected :delay to be an integer >= 1, got 0.25", fn ->
      ClientWithFloatDelay.get("/ok")
    end
  end

  test "ensures max_delay option is positive" do
    defmodule ClientWithNegativeMaxDelay do
      use Tesla
      plug Tesla.Middleware.Retry, max_delay: -1
      adapter LaggyAdapter
    end

    assert_raise ArgumentError, "expected :max_delay to be an integer >= 1, got -1", fn ->
      ClientWithNegativeMaxDelay.get("/ok")
    end
  end

  test "ensures max_delay option is an integer" do
    defmodule ClientWithStringMaxDelay do
      use Tesla
      plug Tesla.Middleware.Retry, max_delay: "500"
      adapter LaggyAdapter
    end

    assert_raise ArgumentError, "expected :max_delay to be an integer >= 1, got \"500\"", fn ->
      ClientWithStringMaxDelay.get("/ok")
    end
  end

  test "ensures max_retries option is not negative" do
    defmodule ClientWithNegativeMaxRetries do
      use Tesla
      plug Tesla.Middleware.Retry, max_retries: -1
      adapter LaggyAdapter
    end

    assert_raise ArgumentError, "expected :max_retries to be an integer >= 0, got -1", fn ->
      ClientWithNegativeMaxRetries.get("/ok")
    end
  end

  test "ensures jitter_factor option is a float between 0 and 1" do
    defmodule ClientWithJitterFactorLt0 do
      use Tesla
      plug Tesla.Middleware.Retry, jitter_factor: -0.1
      adapter LaggyAdapter
    end

    defmodule ClientWithJitterFactorGt1 do
      use Tesla
      plug Tesla.Middleware.Retry, jitter_factor: 1.1
      adapter LaggyAdapter
    end

    assert_raise ArgumentError,
                 "expected :jitter_factor to be a float >= 0 and <= 1, got -0.1",
                 fn ->
                   ClientWithJitterFactorLt0.get("/ok")
                 end

    assert_raise ArgumentError,
                 "expected :jitter_factor to be a float >= 0 and <= 1, got 1.1",
                 fn ->
                   ClientWithJitterFactorGt1.get("/ok")
                 end
  end
end
