defmodule Tesla.Middleware.RetryTest do
  use ExUnit.Case, async: false

  defmodule LaggyAdapter do
    def start_link,
      do:
        Agent.start_link(fn -> %{retries: 0, start_time: DateTime.utc_now()} end,
          name: __MODULE__
        )

    def reset(),
      do: Agent.update(__MODULE__, fn _ -> %{retries: 0, start_time: DateTime.utc_now()} end)

    def call(env, _opts) do
      Agent.get_and_update(__MODULE__, fn %{retries: retries, start_time: start_time} = state ->
        ms_elapsed = DateTime.diff(DateTime.utc_now(), start_time, :millisecond)

        response =
          case env.url do
            "/ok" ->
              {:ok, env}

            "/maybe" when retries == 2 ->
              {:error, :nxdomain}

            "/maybe" when retries < 5 ->
              {:error, :econnrefused}

            "/maybe" ->
              {:ok, env}

            "/nope" ->
              {:error, :econnrefused}

            "/retry_status" when retries < 5 ->
              {:ok, %{env | status: 500}}

            "/retry_status" ->
              {:ok, %{env | status: 200}}

            "/retry_after_seconds" when ms_elapsed < 1000 ->
              {:ok, %{env | status: 429, headers: [{"retry-after", "2"} | env.headers]}}

            "/retry_after_seconds" ->
              {:ok, %{env | status: 200}}

            "/retry_after_date" when ms_elapsed < 1000 ->
              {:ok,
               %{
                 env
                 | status: 429,
                   headers: [
                     {"retry-after",
                      Calendar.strftime(
                        DateTime.add(start_time, 2, :second),
                        "%a, %d %b %Y %H:%M:%S GMT"
                      )}
                     | env.headers
                   ]
               }}

            "/retry_after_date" ->
              {:ok, %{env | status: 200}}

            "/retry_after_invalid" when retries < 5 ->
              {:ok, %{env | status: 429, headers: [{"retry-after", "foo"} | env.headers]}}

            "/retry_after_invalid" ->
              {:ok, %{env | status: 200}}
          end

        {response, %{state | retries: retries + 1}}
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
        {:ok, %{status: status}}, _env, _context when status in [400, 500] ->
          true

        {:ok, _reason}, _env, _context ->
          false

        {:error, _reason}, %Tesla.Env{method: :post}, _context ->
          false

        {:error, _reason}, %Tesla.Env{method: :put}, %{retries: 2} ->
          false

        {:error, _reason}, _env, _context ->
          true
      end

    adapter LaggyAdapter
  end

  defmodule ClientUsingRetryAfterHeader do
    use Tesla

    plug Tesla.Middleware.Retry,
      delay: 10,
      max_retries: 10,
      use_retry_after_header: true,
      should_retry: fn
        {:ok, %{status: status}}, _env, _context when status in [429] ->
          true

        {:ok, _reason}, _env, _context ->
          false
      end

    adapter LaggyAdapter
  end

  setup_all do
    {:ok, _pid} = LaggyAdapter.start_link()
    :ok
  end

  setup do
    LaggyAdapter.reset()
    :ok
  end

  test "pass on successful request" do
    assert {:ok, %Tesla.Env{url: "/ok", method: :get}} = Client.get("/ok")
  end

  test "finally pass on laggy request" do
    assert {:ok, %Tesla.Env{url: "/maybe", method: :get}} = Client.get("/maybe")
  end

  test "pass retry_count opt" do
    assert {:ok, env} = Client.get("/maybe")
    assert env.opts[:retry_count] == 5

    assert {:ok, env} = Client.get("/ok")
    assert env.opts[:retry_count] == nil
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

  test "use custom retry determination function matching on env" do
    assert {:error, :econnrefused} = ClientWithShouldRetryFunction.post("/maybe", "payload")
  end

  test "use custom retry determination function matching on context" do
    assert {:error, :nxdomain} = ClientWithShouldRetryFunction.put("/maybe", "payload")
  end

  test "use Retry-After header when it is a integer number of seconds" do
    assert {:ok, %Tesla.Env{url: "/retry_after_seconds", method: :get, status: 200}} =
             ClientUsingRetryAfterHeader.get("/retry_after_seconds")

    assert Agent.get(LaggyAdapter, fn %{retries: retries} -> retries end) == 2
  end

  test "use Retry-After header when it is a HTTP Date string" do
    assert {:ok, %Tesla.Env{url: "/retry_after_date", method: :get, status: 200}} =
             ClientUsingRetryAfterHeader.get("/retry_after_date")

    assert Agent.get(LaggyAdapter, fn %{retries: retries} -> retries end) == 2
  end

  test "ingore Retry-After header if it is not in an expected format" do
    assert {:ok, %Tesla.Env{url: "/retry_after_invalid", method: :get, status: 200}} =
             ClientUsingRetryAfterHeader.get("/retry_after_invalid")

    assert Agent.get(LaggyAdapter, fn %{retries: retries} -> retries end) == 6
  end

  test "do not retry if Retry-After delay exceeds max delay" do
    defmodule ClientUsingRetryAfterHeaderWithMaxDelay do
      use Tesla

      plug Tesla.Middleware.Retry,
        delay: 10,
        max_delay: 500,
        max_retries: 10,
        use_retry_after_header: true,
        should_retry: fn
          {:ok, %{status: status}}, _env, _context when status in [429] ->
            true

          {:ok, _reason}, _env, _context ->
            false
        end

      adapter LaggyAdapter
    end

    assert {:ok, %Tesla.Env{url: "/retry_after_seconds", method: :get, status: 429}} =
             ClientUsingRetryAfterHeaderWithMaxDelay.get("/retry_after_seconds")

    assert Agent.get(LaggyAdapter, fn %{retries: retries} -> retries end) == 1
  end

  test "jitter doesn't allow delay to be shorter than specified by Retry-After heade or larger than max delay" do
    defmodule ClientUsingRetryAfterHeaderWithHighJitter do
      use Tesla

      plug Tesla.Middleware.Retry,
        delay: 10,
        max_delay: 2001,
        max_retries: 1,
        jitter_factor: 0.9999,
        use_retry_after_header: true,
        should_retry: fn
          {:ok, %{status: status}}, _env, _context when status in [429] ->
            true

          {:ok, _reason}, _env, _context ->
            false
        end

      adapter LaggyAdapter
    end

    assert {:ok, %Tesla.Env{url: "/retry_after_seconds", method: :get, status: 200}} =
             ClientUsingRetryAfterHeaderWithHighJitter.get("/retry_after_seconds")

    finish_time = :os.system_time(:millisecond)

    # need to allow some time for the request handling; should be small relative to max_delay to minimize probability of false negatives
    allowed_execution_ms = 100

    %{retries: retries, start_time: start_time} = Agent.get(LaggyAdapter, fn state -> state end)

    assert retries == 2

    assert finish_time < DateTime.to_unix(start_time, :millisecond) + 2001 + allowed_execution_ms
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

  test "ensures should_retry option is a function with arity of 1 or 3" do
    defmodule ClientWithShouldRetryArity0 do
      use Tesla
      plug Tesla.Middleware.Retry, should_retry: fn -> true end
      adapter LaggyAdapter
    end

    defmodule ClientWithShouldRetryArity2 do
      use Tesla
      plug Tesla.Middleware.Retry, should_retry: fn _res, _env -> true end
      adapter LaggyAdapter
    end

    assert_raise ArgumentError,
                 ~r/expected :should_retry to be a function with arity of 1 or 3, got #Function<\d.\d+\/0/,
                 fn ->
                   ClientWithShouldRetryArity0.get("/ok")
                 end

    assert_raise ArgumentError,
                 ~r/expected :should_retry to be a function with arity of 1 or 3, got #Function<\d.\d+\/2/,
                 fn ->
                   ClientWithShouldRetryArity2.get("/ok")
                 end
  end

  test "ensures use_retry_after_header is a boolean" do
    defmodule ClientWithStringUseRetryAfterHeader do
      use Tesla
      plug Tesla.Middleware.Retry, use_retry_after_header: 1
      adapter LaggyAdapter
    end

    assert_raise ArgumentError,
                 ~r/expected :use_retry_after_header to be a boolean, got 1/,
                 fn ->
                   ClientWithStringUseRetryAfterHeader.get("/ok")
                 end
  end
end
