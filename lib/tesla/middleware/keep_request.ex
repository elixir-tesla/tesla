defmodule Tesla.Middleware.KeepRequest do
  @moduledoc """
  Store request body & headers into opts.

  ## Example

  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.KeepRequest
  end

  {:ok, env} = MyClient.post("/", "request-data")

  env.body
  # => "response-data"

  env.opts[:req_body]
  # => "request-data"

  env.opts[:req_headers]
  # => [{"request-headers", "are-safe"}, ...]
  ```
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, _opts) do
    env
    |> Tesla.put_opt(:req_body, env.body)
    |> Tesla.put_opt(:req_headers, env.headers)
    |> Tesla.run(next)
  end
end
