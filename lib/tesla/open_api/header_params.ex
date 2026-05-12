defmodule Tesla.OpenAPI.HeaderParams do
  @moduledoc """
  Precompiled header parameter definitions.

  `Tesla.OpenAPI.HeaderParams` keeps static header parameter metadata separate
  from per-request values. Generated clients can build it once and pass only
  dynamic values when creating request headers.

      alias Tesla.OpenAPI.{HeaderParam, HeaderParams}

      header_params =
        HeaderParams.new!([
          HeaderParam.new!("X-Request-ID")
        ])

      HeaderParams.to_headers(header_params, %{"X-Request-ID" => "req-123"})
  """

  alias Tesla.OpenAPI.HeaderParam

  @enforce_keys [:definitions, :by_name]
  defstruct [:definitions, :by_name]

  @opaque t :: %__MODULE__{
            definitions: [HeaderParam.t()],
            by_name: %{String.t() => HeaderParam.t()}
          }

  @spec new!([HeaderParam.t()]) :: t()
  def new!(definitions) when is_list(definitions) do
    %__MODULE__{definitions: definitions, by_name: by_name!(definitions)}
  end

  @doc false
  @spec definitions(t()) :: [HeaderParam.t()]
  def definitions(%__MODULE__{definitions: definitions}) do
    definitions
  end

  @doc false
  @spec fetch(t(), String.t()) :: {:ok, %HeaderParam{}} | :error
  def fetch(%__MODULE__{by_name: by_name}, name) when is_binary(name) do
    Map.fetch(by_name, name)
  end

  @spec to_headers(t(), map() | nil) :: Tesla.Env.headers()
  def to_headers(%__MODULE__{}, nil) do
    []
  end

  def to_headers(%__MODULE__{definitions: definitions}, values) when is_map(values) do
    {headers, _values} = Enum.reduce(definitions, {[], values}, &put_header/2)
    Enum.reverse(headers)
  end

  def to_headers(%__MODULE__{}, values) do
    raise ArgumentError,
          "expected header parameter values to be a map; got #{inspect(values)}"
  end

  defp put_header(%HeaderParam{name: name} = header_param, {headers, values}) do
    case Map.fetch(values, name) do
      {:ok, value} ->
        {[{name, HeaderParam.serialize(header_param, value)} | headers], values}

      :error ->
        {headers, values}
    end
  end

  defp by_name!(definitions) do
    Enum.reduce(definitions, %{}, &put_by_name!/2)
  end

  defp put_by_name!(%HeaderParam{name: name} = header_param, by_name) do
    case Map.has_key?(by_name, name) do
      true ->
        raise ArgumentError, "duplicate header parameter #{inspect(name)}"

      false ->
        Map.put(by_name, name, header_param)
    end
  end

  defp put_by_name!(value, _by_name) do
    raise ArgumentError,
          "expected header parameter definitions to be #{inspect(HeaderParam)} structs; got #{inspect(value)}"
  end
end
