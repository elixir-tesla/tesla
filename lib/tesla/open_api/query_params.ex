defmodule Tesla.OpenAPI.QueryParams do
  @moduledoc """
  A collection of query parameter definitions for `Tesla.Middleware.Query`.

  `Tesla.OpenAPI.QueryParams` keeps static query parameter metadata separate from
  per-request values. Since query parameter definitions usually come from a
  static operation specification, prefer defining the collection in a module
  attribute, storing it in request private data, and passing only dynamic values
  through `env.query`.

      defmodule MyApi.Operation.ListItems do
        alias Tesla.OpenAPI.{QueryParam, QueryParams}

        @query_params QueryParams.new!([
                        QueryParam.new!("filter"),
                        QueryParam.new!("ids", style: :pipe_delimited)
                      ])

        @private QueryParams.put_private(@query_params)

        def request(client) do
          Tesla.get(client, "/items",
            query: %{
              "filter" => [status: "open", owner: "yordis"],
              "ids" => [10, 20],
              "debug" => true
            },
            private: @private
          )
        end
      end
  """

  alias Tesla.OpenAPI.QueryParam
  alias Tesla.Param

  @enforce_keys [:definitions]
  defstruct [:definitions]

  @opaque t :: %__MODULE__{
            definitions: [QueryParam.t()]
          }

  @private_key :tesla_query_params

  @spec new!([QueryParam.t()]) :: t()
  def new!(definitions) when is_list(definitions) do
    %__MODULE__{definitions: Param.validate_definitions!(definitions, QueryParam, :query)}
  end

  @doc """
  Adds query parameter definitions to Tesla request private data.

      defmodule MyApi.Operation.ListItems do
        @query_params Tesla.OpenAPI.QueryParams.new!([Tesla.OpenAPI.QueryParam.new!("page")])
        @private Tesla.OpenAPI.QueryParams.put_private(@query_params)

        def request(client) do
          Tesla.get(client, "/items",
            query: %{"page" => 2},
            private: @private
          )
        end
      end
  """
  @spec put_private(t()) :: Tesla.Env.private()
  def put_private(%__MODULE__{} = query_params) do
    put_private(%{}, query_params)
  end

  @spec put_private(Tesla.Env.private(), t()) :: Tesla.Env.private()
  def put_private(private, %__MODULE__{} = query_params) when is_map(private) do
    Map.put(private, @private_key, query_params)
  end

  @doc false
  @spec fetch_private(Tesla.Env.private()) :: {:ok, t()} | :error
  def fetch_private(private) when is_map(private) do
    case Map.fetch(private, @private_key) do
      {:ok, %__MODULE__{} = query_params} ->
        {:ok, query_params}

      {:ok, _value} ->
        :error

      :error ->
        :error
    end
  end

  @doc false
  @spec definitions(t()) :: [QueryParam.t()]
  def definitions(%__MODULE__{definitions: definitions}) do
    definitions
  end
end
