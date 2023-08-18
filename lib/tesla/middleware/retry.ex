defmodule Tesla.Middleware.Retry do
  @moduledoc """
  Retry using exponential backoff and full jitter.

  By defaults, this middleware only retries in the case of connection errors (`nxdomain`, `connrefused`, etc).
  Application error checking for retry can be customized through `:should_retry` option.

  ## Backoff algorithm

  The backoff algorithm optimizes for tight bounds on completing a request successfully.
  It does this by first calculating an exponential backoff factor based on the
  number of retries that have been performed.  It then multiplies this factor against
  the base delay. The total maximum delay is found by taking the minimum of either
  the calculated delay or the maximum delay specified. This creates an upper bound
  on the maximum delay we can see.

  In order to find the actual delay value we apply additive noise which is proportional
  to the current desired delay. This ensures that the actual delay is kept within
  the expected order of magnitude, while still having some randomness, which ensures
  that our retried requests don't "harmonize" making it harder for the downstream service to heal.

  ## Examples

  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.Retry,
      delay: 500,
      max_retries: 10,
      max_delay: 4_000,
      should_retry: fn
        {:ok, %{status: status}} when status in [400, 500] -> true
        {:ok, _} -> false
        {:error, _} -> true
      end
      # or
      plug Tesla.Middleware.Retry, should_retry: fn
        {:ok, %{status: status}}, _env, _context when status in [400, 500] -> true
        {:ok, _reason}, _env, _context -> false
        {:error, _reason}, %Tesla.Env{method: :post}, _context -> false
        {:error, _reason}, %Tesla.Env{method: :put}, %{retries: 2} -> false
        {:error, _reason}, _env, _context -> true
      end
  end
  ```

  ## Options

  - `:delay` - The base delay in milliseconds (positive integer, defaults to 50)
  - `:max_retries` - maximum number of retries (non-negative integer, defaults to 5)
  - `:max_delay` - maximum delay in milliseconds (positive integer, defaults to 5000)
  - `:should_retry` - function with an arity of 1 or 3 used to determine if the request should
      be retried the first argument is the result, the second is the env and the third is
      the context: options + `:retries` (defaults to a match on `{:error, _reason}`)
  - `:jitter_factor` - additive noise proportionality constant
      (float between 0 and 1, defaults to 0.2)
  """

  @behaviour Tesla.Middleware

  @defaults [
    delay: 50,
    max_retries: 5,
    max_delay: 5_000,
    jitter_factor: 0.2
  ]

  @impl Tesla.Middleware
  def call(env, next, opts) do
    opts = opts || []

    context = %{
      retries: 0,
      delay: integer_opt!(opts, :delay, 1),
      max_retries: integer_opt!(opts, :max_retries, 0),
      max_delay: integer_opt!(opts, :max_delay, 1),
      should_retry: should_retry_opt!(opts),
      jitter_factor: float_opt!(opts, :jitter_factor, 0, 1)
    }

    retry(env, next, context)
  end

  # If we have max retries set to 0 don't retry
  defp retry(env, next, %{max_retries: 0}), do: Tesla.run(env, next)

  # If we're on our last retry then just run and don't handle the error
  defp retry(env, next, %{max_retries: max, retries: max}) do
    Tesla.run(env, next)
  end

  # Otherwise we retry if we get a retriable error
  defp retry(env, next, context) do
    res = Tesla.run(env, next)

    {:arity, should_retry_arity} = :erlang.fun_info(context.should_retry, :arity)

    cond do
      should_retry_arity == 1 and context.should_retry.(res) ->
        do_retry(env, next, context)

      should_retry_arity == 3 and context.should_retry.(res, env, context) ->
        do_retry(env, next, context)

      true ->
        res
    end
  end

  defp do_retry(env, next, context) do
    backoff(context.max_delay, context.delay, context.retries, context.jitter_factor)
    context = update_in(context, [:retries], &(&1 + 1))
    retry(env, next, context)
  end

  # Exponential backoff with jitter
  defp backoff(cap, base, attempt, jitter_factor) do
    factor = Bitwise.bsl(1, attempt)
    max_sleep = min(cap, base * factor)

    # This ensures that the delay's order of magnitude is kept intact, while still having some jitter.
    # Generates a value x where 1 - jitter_factor <= x <= 1
    jitter = 1 - jitter_factor * :rand.uniform()

    # The actual delay is in the range max_sleep * (1 - jitter_factor) <= delay <= max_sleep
    delay = trunc(max_sleep * jitter)

    :timer.sleep(delay)
  end

  defp integer_opt!(opts, key, min) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_integer(value) and value >= min -> value
      {:ok, invalid} -> invalid_integer(key, invalid, min)
      :error -> @defaults[key]
    end
  end

  defp float_opt!(opts, key, min, max) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_float(value) and value >= min and value <= max -> value
      {:ok, invalid} -> invalid_float(key, invalid, min, max)
      :error -> @defaults[key]
    end
  end

  defp should_retry_opt!(opts) do
    case Keyword.get(opts, :should_retry, &match?({:error, _}, &1)) do
      should_retry_fun when is_function(should_retry_fun, 1) ->
        should_retry_fun

      should_retry_fun when is_function(should_retry_fun, 3) ->
        should_retry_fun

      value ->
        invalid_should_retry_fun(value)
    end
  end

  defp invalid_integer(key, value, min) do
    raise(ArgumentError, "expected :#{key} to be an integer >= #{min}, got #{inspect(value)}")
  end

  defp invalid_float(key, value, min, max) do
    raise(
      ArgumentError,
      "expected :#{key} to be a float >= #{min} and <= #{max}, got #{inspect(value)}"
    )
  end

  defp invalid_should_retry_fun(value) do
    raise(
      ArgumentError,
      "expected :should_retry to be a function with arity of 1 or 3, got #{inspect(value)}"
    )
  end
end
