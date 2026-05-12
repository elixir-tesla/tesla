defmodule Tesla.OpenAPI do
  @moduledoc """
  Helpers for OpenAPI-compatible generated clients.

  Generated clients can precompute OpenAPI parameter definitions as module
  attributes and merge their request private data once:

      @private Tesla.OpenAPI.merge_private([
                 Tesla.OpenAPI.PathTemplate.put_private(@path_template),
                 Tesla.OpenAPI.PathParams.put_private(@path_params),
                 Tesla.OpenAPI.QueryParams.put_private(@query_params)
               ])
  """

  @doc """
  Merges request private data maps from left to right.
  """
  @spec merge_private([Tesla.Env.private()]) :: Tesla.Env.private()
  def merge_private(privates) when is_list(privates) do
    Enum.reduce(privates, %{}, &merge_private/2)
  end

  defp merge_private(private, merged) when is_map(private) do
    Map.merge(merged, private)
  end
end
