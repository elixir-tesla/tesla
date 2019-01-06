defmodule Tesla.Middleware.Retry do
  @behaviour Tesla.Middleware

  @moduledoc """
  Retry few times in case of connection error (`nxdomain`, `connrefused` etc).
  This middleware will NOT retry in case of application error (HTTP status 5xx).

  ### Example
  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.Retry, delay: 500, max_retries: 10
  end
  ```

  ### Options
  - `:delay`        - number of milliseconds to wait before retrying (defaults to 1000)
  - `:max_retries`  - maximum number of retries (defaults to 5)
  - `:should_retry` - function to determine it should be retried
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
    if should_retry.(Tesla.run(env, next)) do
      :timer.sleep(delay)
      retry(env, next, delay, retries - 1, should_retry)
    else
      {:ok, env}
    end
  end
end
