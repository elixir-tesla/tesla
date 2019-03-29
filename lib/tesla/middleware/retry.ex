defmodule Tesla.Middleware.Retry do
  @behaviour Tesla.Middleware

  @moduledoc """
  Retry the HTTP call in case of connection error by default (`nxdomain`, `connrefused` etc).
  Application error checking for retry can be customized through should_retry options by
  providing a function in returning a boolean.

  ### Example
  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.Retry,
      delay: 500,
      max_retries: 10,
      should_retry: fn
        {:ok, %{status: status}} when status in [400, 500] -> true
        {:ok, _} -> false
        {:error, _} -> true
      end
  end
  ```

  ### Options
  - `:delay`        - number of milliseconds to wait before retrying (defaults to 1000)
  - `:max_retries`  - maximum number of retries (defaults to 5)
  - `:should_retry` - function to determine if request should be retried
  """

  @defaults [
    delay: 1000,
    max_retries: 5
  ]

  @doc false
  def call(env, next, opts) do
    opts = opts || []
    delay = Keyword.get(opts, :delay, @defaults[:delay])
    max_retries = Keyword.get(opts, :max_retries, @defaults[:max_retries])
    should_retry = Keyword.get(opts, :should_retry, &match?({:error, _}, &1))

    retry(env, next, delay, max_retries, should_retry)
  end

  defp retry(env, next, _delay, retries, _should_retry) when retries <= 1 do
    Tesla.run(env, next)
  end

  defp retry(env, next, delay, retries, should_retry) do
    res = Tesla.run(env, next)

    if should_retry.(res) do
      :timer.sleep(delay)
      retry(env, next, delay, retries - 1, should_retry)
    else
      res
    end
  end
end
