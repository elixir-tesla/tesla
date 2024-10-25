defmodule Tesla.Middleware.Headers do
  @moduledoc """
  Set default headers for all requests

  ## Examples

  ```elixir
  defmodule Myclient do
    def client do
      Tesla.client([
        {Tesla.Middleware.Headers, [{"user-agent", "Tesla"}]}
      ])
    end
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
