defmodule Tesla.Middleware.KeepRequest do
  @behaviour Tesla.Middleware

  @moduledoc """
  Store request body & headers into opts.

  ### Example
  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.KeepRequest
  end

  {:ok, env} = MyClient.post("/", "request-data")
  env.body # => "response-data"
  env.opts[:req_body] # => "request-data"
  ```
  """
  def call(env, next, _opts) do
    env
    |> Tesla.put_opt(:req_body, env.body)
    |> Tesla.put_opt(:req_headers, env.headers)
    |> Tesla.run(next)
  end
end
