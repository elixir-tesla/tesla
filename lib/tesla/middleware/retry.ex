defmodule Tesla.Middleware.Retry do
  @moduledoc """
  Retry few times in case of connection refused error.

  Example:
      defmodule MyClient do
        use Tesla

        plug Tesla.Middleware.Retry, delay: 500, max_retries: 10
      end

  Options:
  - `:delay`        - number of milisecond to wait before retrying (defaults to 1000)
  - `:max_retries`  - maximum number of retries (defaults to 5)
  """

  @defaults [
    delay:        1000,
    max_retries:  5
  ]

  def call(env, next, opts) do
    opts    = opts || []
    delay       = Keyword.get(opts, :delay,       @defaults[:delay])
    max_retries = Keyword.get(opts, :max_retries, @defaults[:max_retries])

    retry(env, next, delay, max_retries)
  end

  defp retry(env, next, _delay, retries) when retries <= 1 do
    Tesla.run(env, next)
  end

  defp retry(env, next, delay, retries) do
    Tesla.run(env, next)
  rescue
    error -> case error do
      %Tesla.Error{} ->
        :timer.sleep(delay)
        retry(env, next, delay, retries - 1)

      _ ->
        reraise error, System.stacktrace
    end
  end
end
