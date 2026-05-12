defmodule Tesla.OpenAPI.PathParams do
  @moduledoc """
  Precompiled path parameter definitions for `Tesla.Middleware.PathParams`.

  `Tesla.OpenAPI.PathParams` keeps static path parameter metadata separate from
  per-request values. Generated clients can build it once, store it in request
  private data, and pass only the dynamic values through `opts[:path_params]`.

      alias Tesla.OpenAPI.{PathParam, PathParams}

      path_params =
        PathParams.new!([
          PathParam.new!("id"),
          PathParam.new!("coords", style: :matrix, explode: true)
        ])

      private = PathParams.put_private(path_params)

      Tesla.get(client, "/items/{id}{coords}",
        opts: [path_params: %{"id" => 5, "coords" => ["blue", "black"]}],
        private: private
      )
  """

  alias Tesla.OpenAPI.PathParam

  @enforce_keys [:definitions]
  defstruct [:definitions]

  @opaque t :: %__MODULE__{
            definitions: %{String.t() => PathParam.t()}
          }

  @private_key :tesla_path_params

  @spec new!([PathParam.t()]) :: t()
  def new!(definitions) when is_list(definitions) do
    %__MODULE__{definitions: by_name!(definitions)}
  end

  @doc """
  Adds path parameter definitions to Tesla request private data.

      path_params = Tesla.OpenAPI.PathParams.new!([Tesla.OpenAPI.PathParam.new!("id")])
      private = Tesla.OpenAPI.PathParams.put_private(path_params)

      Tesla.get(client, "/items/{id}",
        opts: [path_params: %{"id" => 42}],
        private: private
      )
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

  defp by_name!(definitions) do
    Enum.reduce(definitions, %{}, &put_definition_by_name!/2)
  end

  defp put_definition_by_name!(%PathParam{name: name} = path_param, definitions) do
    case Map.has_key?(definitions, name) do
      true ->
        raise ArgumentError, "duplicate path parameter #{inspect(name)}"

      false ->
        Map.put(definitions, name, path_param)
    end
  end

  defp put_definition_by_name!(value, _definitions) do
    raise ArgumentError,
          "expected path parameter definitions to be #{inspect(PathParam)} structs; got #{inspect(value)}"
  end
end
