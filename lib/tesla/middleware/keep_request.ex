defmodule Tesla.Middleware.KeepRequest do
  @moduledoc """
  Store request URL, body, and headers into `:opts`.

  ## Examples

  ```
  defmodule MyClient do
    def client do
      Tesla.client([
        Tesla.Middleware.KeepRequest,
        Tesla.Middleware.PathParams
      ])
    end
  end

  client = MyClient.client()
  {:ok, env} = Tesla.post(client, "/users/:user_id", "request-data", opts: [path_params: [user_id: "1234"]])

  env.body
  # => "response-data"

  env.opts[:req_body]
  # => "request-data"

  env.opts[:req_headers]
  # => [{"request-headers", "are-safe"}, ...]

  env.opts[:req_url]
  # => "http://localhost:8000/users/:user_id
  ```

  ## Observability

  In practice, you would combine `Tesla.Middleware.KeepRequest`, `Tesla.Middleware.PathParams`, and
  `Tesla.Middleware.Telemetry` to observe the request and response data.
  Keep in mind that the request order matters. Make sure to put `Tesla.Middleware.KeepRequest` before
  `Tesla.Middleware.PathParams` to make sure that the request data is stored before the path parameters are replaced.
  While keeping in mind that this is an application-specific concern, this is the overall recommendation.
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
