defmodule Tesla.Middleware.Query do
  @moduledoc """
  Set default query params for all requests

  ## Examples

  ```elixir
  defmodule MyClient do
    def client do
      Tesla.client([
        {Tesla.Middleware.Query, [token: "some-token"]}
      ])
    end
  end
  ```
  """

  @behaviour Tesla.Middleware

  alias Tesla.Middleware.Query.Modern

  @impl Tesla.Middleware
  def call(env, next, mode: :modern), do: Modern.call(env, next)

  def call(env, next, query) do
    env
    |> merge(query)
    |> Tesla.run(next)
  end

  defp merge(env, nil), do: env

  defp merge(env, query) do
    Map.update!(env, :query, &merge_query_params(&1, query))
  end

  defp merge_query_params(existing, query) when is_map(existing) and is_map(query) do
    Map.merge(query, existing)
  end

  defp merge_query_params(existing, query) do
    to_query_list(existing) ++ to_query_list(query)
  end

  defp to_query_list(query) when is_map(query), do: Map.to_list(query)
  defp to_query_list(query), do: List.wrap(query)
end
