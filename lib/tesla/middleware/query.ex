defmodule Tesla.Middleware.Query do
  @moduledoc """
  Set default query params or serialize OpenAPI-style query values.

  ## Default Query Params

  Pass a keyword list or map as the middleware argument to merge default query
  params into every request:

  ```elixir
  defmodule MyClient do
    def client do
      Tesla.client([
        {Tesla.Middleware.Query, [token: "some-token"]}
      ])
    end
  end
  ```

  ## Modern OpenAPI Query Params

  Use `mode: :modern` with `Tesla.OpenAPI.QueryParams` when generated clients need the
  OpenAPI query parameter styles `:form`, `:space_delimited`,
  `:pipe_delimited`, or `:deep_object`. Store the static parameter definitions
  in request private data, then pass request values as a map. Other query params
  remain normal Tesla query params:

  ```elixir
  query_params =
    Tesla.OpenAPI.QueryParams.new!([
      Tesla.OpenAPI.QueryParam.new!("filter"),
      Tesla.OpenAPI.QueryParam.new!("ids", style: :pipe_delimited)
    ])

  private = Tesla.OpenAPI.QueryParams.put_private(query_params)

  client = Tesla.client([{Tesla.Middleware.Query, mode: :modern}])

  Tesla.get(client, "/items",
    query: %{
      "filter" => [status: "open", owner: "yordis"],
      "ids" => [1, 2, 3],
      "debug" => true
    },
    private: private
  )
  ```

  Object-valued query params cover OpenAPI schemas with `additionalProperties`.
  Unknown top-level query params, such as `"debug"` above, pass through as
  normal Tesla query params.
  """

  @behaviour Tesla.Middleware

  alias Tesla.Middleware.Query.Modern
  alias Tesla.OpenAPI.QueryString
  alias Tesla.OpenAPI.QueryStringError

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

  defp merge_query_params(%QueryString{} = existing, query) do
    case empty_query?(query) do
      true -> existing
      false -> raise_mixed_query_string!(query)
    end
  end

  defp merge_query_params(existing, %QueryString{} = query) do
    case empty_query?(existing) do
      true -> query
      false -> raise_mixed_query_string!(existing)
    end
  end

  defp merge_query_params(existing, query) when is_map(existing) and is_map(query) do
    Map.merge(query, existing)
  end

  defp merge_query_params(existing, query) do
    to_query_list(existing) ++ to_query_list(query)
  end

  defp empty_query?(nil), do: true
  defp empty_query?([]), do: true
  defp empty_query?(query) when is_map(query), do: map_size(query) == 0
  defp empty_query?(_query), do: false

  defp raise_mixed_query_string!(query) do
    raise QueryStringError, reason: :mixed_query_params, query: query
  end

  defp to_query_list(query) when is_map(query), do: Map.to_list(query)
  defp to_query_list(query), do: List.wrap(query)
end
