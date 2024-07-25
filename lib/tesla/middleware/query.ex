defmodule Tesla.Middleware.Query do
  @moduledoc """
  Set default query params for all requests

  ## Examples

  ```
  defmodule Myclient do
    use Tesla

    plug Tesla.Middleware.Query, [token: "some-token"]
  end
  ```
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, query) do
    env
    |> merge(query)
    |> Tesla.run(next)
  end

  defp merge(env, nil), do: env

  defp merge(env, query) do
    Map.update!(env, :query, &(&1 ++ query))
  end
end
