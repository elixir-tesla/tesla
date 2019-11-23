defmodule Tesla.Middleware.Retry do
  @moduledoc """
  Retry using exponential backoff and full jitter. This middleware only retries in the
  case of connection errors (`nxdomain`, `connrefused` etc). Application error
  checking for retry can be customized through `:should_retry` option by
  providing a function in returning a boolean.

  ## Backoff algorithm

  The backoff algorithm optimizes for tight bounds on completing a request successfully.
  It does this by first calculating an exponential backoff factor based on the
  number of retries that have been performed. It then multiplies this factor against the
  base delay. The total maximum delay is found by taking the minimum of either the calculated delay
  or the maximum delay specified. This creates an upper bound on the maximum delay
  we can see.

  In order to find the actual delay value we take a random number between 0 and
  the maximum delay based on a uniform distribution. This randomness ensures that
  our retried requests don't "harmonize" making it harder for the downstream
  service to heal.

  ## Example

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
  end
  ```

  ## Options

  - `:delay` - The base delay in milliseconds (defaults to 50)
  - `:max_retries` - maximum number of retries (defaults to 5)
  - `:max_delay` - maximum delay in milliseconds (defaults to 5000)
  - `:should_retry` - function to determine if request should be retried
  """

  @behaviour Tesla.Middleware

  @defaults [
    delay: 50,
    max_retries: 5,
    max_delay: 5_000
  ]

  @impl Tesla.Middleware
  def call(env, next, opts) do
    opts = opts || []

    context = %{
      retries: 0,
      delay: Keyword.get(opts, :delay, @defaults[:delay]),
      max_retries: Keyword.get(opts, :max_retries, @defaults[:max_retries]),
      max_delay: Keyword.get(opts, :max_delay, @defaults[:max_delay]),
      should_retry: Keyword.get(opts, :should_retry, &match?({:error, _}, &1))
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

    if context.should_retry.(res) do
      backoff(context.max_delay, context.delay, context.retries)
      context = update_in(context, [:retries], &(&1 + 1))
      retry(env, next, context)
    else
      res
    end
  end

  # Exponential backoff with jitter
  defp backoff(cap, base, attempt) do
    factor = :math.pow(2, attempt)
    max_sleep = trunc(min(cap, base * factor))
    delay = :rand.uniform(max_sleep)

    :timer.sleep(delay)
  end
end
