defmodule Tesla.Middleware.KeepRequest do
  @moduledoc """
  Store request url ,body and headers into `:opts`.

  ## Examples

  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.KeepRequest
    plug Tesla.Middleware.PathParams
  end

  {:ok, env} = MyClient.post("/users/:user_id", "request-data", opts: [path_params: [user_id: "1234]])

  env.body
  # => "response-data"

  env.opts[:req_body]
  # => "request-data"

  env.opts[:req_headers]
  # => [{"request-headers", "are-safe"}, ...]

  env.opts[:req_url]
  # => "http://localhost:8000/users/:user_id
  ```
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, _opts) do
    env
    |> Tesla.put_opt(:req_body, env.body)
    |> Tesla.put_opt(:req_headers, env.headers)
    |> Tesla.put_opt(:req_url, env.url)
    |> Tesla.run(next)
  end
end
