defmodule Tesla.QueryParams do
  @moduledoc """
  Precompiled query parameter definitions for `Tesla.Middleware.Query`.

  `Tesla.QueryParams` keeps static query parameter metadata separate from
  per-request values. Generated clients can build it once, store it in request
  private data, and pass only dynamic values through `env.query`.

      alias Tesla.{QueryParam, QueryParams}

      query_params =
        QueryParams.new!([
          QueryParam.new!("filter"),
          QueryParam.new!("ids", style: :pipe_delimited)
        ])

      private = QueryParams.put_private(query_params)

      Tesla.get(client, "/items",
        query: %{
          "filter" => [status: "open", owner: "yordis"],
          "ids" => [10, 20],
          "debug" => true
        },
        private: private
      )
  """

  alias Tesla.QueryParam

  @enforce_keys [:definitions, :by_name]
  defstruct [:definitions, :by_name]

  @opaque t :: %__MODULE__{
            definitions: [QueryParam.t()],
            by_name: %{String.t() => QueryParam.t()}
          }

  @private_key :tesla_query_params

  @spec new!([QueryParam.t()]) :: t()
  def new!(definitions) when is_list(definitions) do
    %__MODULE__{definitions: definitions, by_name: by_name!(definitions)}
  end

  @doc """
  Adds query parameter definitions to Tesla request private data.

      query_params = Tesla.QueryParams.new!([Tesla.QueryParam.new!("page")])
      private = Tesla.QueryParams.put_private(query_params)

      Tesla.get(client, "/items",
        query: %{"page" => 2},
        private: private
      )
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

  @doc false
  @spec fetch(t(), String.t()) :: {:ok, %QueryParam{}} | :error
  def fetch(%__MODULE__{by_name: by_name}, name) when is_binary(name) do
    Map.fetch(by_name, name)
  end

  defp by_name!(definitions) do
    Enum.reduce(definitions, %{}, &put_by_name!/2)
  end

  defp put_by_name!(%QueryParam{name: name} = query_param, by_name) do
    case Map.has_key?(by_name, name) do
      true ->
        raise ArgumentError, "duplicate query parameter #{inspect(name)}"

      false ->
        Map.put(by_name, name, query_param)
    end
  end

  defp put_by_name!(value, _by_name) do
    raise ArgumentError,
          "expected query parameter definitions to be #{inspect(QueryParam)} structs; got #{inspect(value)}"
  end
end
