defmodule Tesla.Middleware.BearerAuth do
  @moduledoc """
  Bearer authentication middleware.

  Adds a `{"authorization", "Bearer <token>"}` header.

  ## Examples

  ```
  defmodule MyClient do
    use Tesla

    # static configuration
    plug Tesla.Middleware.BearerAuth, token: "token"

    # dynamic token
    def new(token) do
      Tesla.client [
        {Tesla.Middleware.BearerAuth, token: token}
      ]
    end
  end
  ```

  ## Options

  - `:token` - token (defaults to `""`)
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts \\ []) do
    token = Keyword.get(opts, :token, "")

    env
    |> Tesla.put_headers([{"authorization", "Bearer #{token}"}])
    |> Tesla.run(next)
  end
end
