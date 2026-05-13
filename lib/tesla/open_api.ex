defmodule Tesla.OpenAPI do
  @moduledoc """
  Reference entry point for OpenAPI-compatible generated clients.

  Tesla does not parse OpenAPI documents or generate operation modules. It
  provides value objects and middleware hooks that generated clients can use
  after they have already interpreted the OpenAPI document.

  ## Parameter Locations

  | OpenAPI location | Tesla API |
  | --- | --- |
  | `path` | `Tesla.OpenAPI.PathTemplate`, `Tesla.OpenAPI.PathParam`, `Tesla.OpenAPI.PathParams`, and `Tesla.Middleware.PathParams` in `:modern` mode |
  | `query` | `Tesla.OpenAPI.QueryParam`, `Tesla.OpenAPI.QueryParams`, and `Tesla.Middleware.Query` in `:modern` mode |
  | `querystring` | `Tesla.OpenAPI.QueryString` passed as the request `:query` |
  | `header` | `Tesla.OpenAPI.HeaderParam` and `Tesla.OpenAPI.HeaderParams.to_headers/2` |
  | `cookie` | `Tesla.OpenAPI.CookieParam` and `Tesla.OpenAPI.CookieParams.to_headers/2` |

  ## Static Metadata And Dynamic Values

  Generated clients should keep OpenAPI parameter definitions as module
  attributes and pass only request values at runtime:

      defmodule MyApi.Operation.GetItem.Path do
        @path_params Tesla.OpenAPI.PathParams.new!([
                       Tesla.OpenAPI.PathParam.new!("id")
                     ])

        def path_params, do: @path_params
      end

      defmodule MyApi.Operation.GetItem.Query do
        @query_params Tesla.OpenAPI.QueryParams.new!([
                        Tesla.OpenAPI.QueryParam.new!("filter")
                      ])

        def query_params, do: @query_params
      end

      defmodule MyApi.Operation.GetItem do
        alias MyApi.Operation.GetItem.{Path, Query}

        @path_template Tesla.OpenAPI.PathTemplate.new!("/items/{id}")

        @private Tesla.OpenAPI.merge_private([
                   Tesla.OpenAPI.PathTemplate.put_private(@path_template),
                   Tesla.OpenAPI.PathParams.put_private(Path.path_params()),
                   Tesla.OpenAPI.QueryParams.put_private(Query.query_params())
                 ])
      end

  Path and query parameter collections are placed in `t:Tesla.Env.private/0`
  because their middleware serializes them into the request URL. Header and
  cookie parameter collections are applied before the request enters the
  middleware stack and produce raw header tuples.

  ## Response Wrappers

  Generated clients can define a local response module with
  `Tesla.OpenAPI.Response`:

      defmodule MyApi.Response do
        use Tesla.OpenAPI.Response
      end

  ## Field Mapping

  `in` chooses the Tesla API. It is not passed as an option to the value
  objects. `style`, `explode`, and `allowReserved` become `:style`, `:explode`,
  and `:allow_reserved` options where the corresponding parameter location
  supports them.

  See [Working with OpenAPI parameters](openapi-parameters.html) for a
  generated-operation walkthrough, or the [OpenAPI Cheat Sheet](openapi.html)
  for quick lookup while implementing generated clients.
  """

  @doc """
  Merges `t:Tesla.Env.private/0` maps from left to right.
  """
  @spec merge_private([Tesla.Env.private()]) :: Tesla.Env.private()
  def merge_private(privates) when is_list(privates) do
    Enum.reduce(privates, %{}, &merge_private/2)
  end

  defp merge_private(private, merged) when is_map(private) do
    Map.merge(merged, private)
  end
end
