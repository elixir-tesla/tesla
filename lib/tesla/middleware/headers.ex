defmodule Tesla.Middleware.Headers do
  @moduledoc """
  Set default headers for all requests

  ## Examples

  ```
  defmodule Myclient do
    use Tesla

    plug Tesla.Middleware.Headers, [{"user-agent", "Tesla"}]
  end
  ```
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, headers) do
    env
    |> Tesla.put_headers(headers)
    |> Tesla.run(next)
  end
end
