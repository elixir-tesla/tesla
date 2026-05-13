defmodule Tesla.OpenAPI.PathParams do
  @moduledoc """
  A collection of path parameter definitions for `Tesla.Middleware.PathParams`.

  `Tesla.OpenAPI.PathParams` keeps static path parameter metadata separate from
  per-request values. Since path parameter definitions usually come from a
  static operation specification, prefer defining the collection in a module
  attribute, storing it in `t:Tesla.Env.private/0`, and passing only the dynamic
  values through `opts[:path_params]`.

      defmodule MyApi.Operation.GetItem do
        alias Tesla.OpenAPI.{PathParam, PathParams}

        @path_params PathParams.new!([
                       PathParam.new!("id"),
                       PathParam.new!("coords", style: :matrix, explode: true)
                     ])

        @private PathParams.put_private(@path_params)

        def request(client) do
          Tesla.get(client, "/items/{id}{coords}",
            opts: [path_params: %{"id" => 5, "coords" => ["blue", "black"]}],
            private: @private
          )
        end
      end
  """

  alias Tesla.OpenAPI.PathParam
  alias Tesla.Param

  @enforce_keys [:definitions]
  defstruct [:definitions]

  @opaque t :: %__MODULE__{
            definitions: %{String.t() => PathParam.t()}
          }

  @private_key :tesla_path_params

  @spec new!([PathParam.t()]) :: t()
  def new!(definitions) when is_list(definitions) do
    definitions =
      definitions
      |> Param.validate_definitions!(PathParam, :path)
      |> Map.new(&definition_by_name/1)

    %__MODULE__{definitions: definitions}
  end

  @doc """
  Adds path parameter definitions to `t:Tesla.Env.private/0`.

      defmodule MyApi.Operation.GetItem do
        @path_params Tesla.OpenAPI.PathParams.new!([Tesla.OpenAPI.PathParam.new!("id")])
        @private Tesla.OpenAPI.PathParams.put_private(@path_params)

        def request(client) do
          Tesla.get(client, "/items/{id}",
            opts: [path_params: %{"id" => 42}],
            private: @private
          )
        end
      end
  """
  @spec put_private(t()) :: Tesla.Env.private()
  def put_private(%__MODULE__{} = path_params) do
    put_private(%{}, path_params)
  end

  @spec put_private(Tesla.Env.private(), t()) :: Tesla.Env.private()
  def put_private(private, %__MODULE__{} = path_params) when is_map(private) do
    Map.put(private, @private_key, path_params)
  end

  @doc false
  @spec fetch_private(Tesla.Env.private()) :: {:ok, t()} | :error
  def fetch_private(private) when is_map(private) do
    case Map.fetch(private, @private_key) do
      {:ok, %__MODULE__{} = path_params} ->
        {:ok, path_params}

      {:ok, _value} ->
        :error

      :error ->
        :error
    end
  end

  @doc false
  @spec fetch(t(), String.t()) :: {:ok, %PathParam{}} | :error
  def fetch(%__MODULE__{definitions: definitions}, name) when is_binary(name) do
    Map.fetch(definitions, name)
  end

  defp definition_by_name(%PathParam{name: name} = definition) do
    {name, definition}
  end
end
