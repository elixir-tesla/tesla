defmodule Tesla.OpenAPI.HeaderParams do
  @moduledoc """
  A collection of header parameter definitions.

  `Tesla.OpenAPI.HeaderParams` keeps static header parameter metadata separate
  from per-request values. Since header parameter definitions usually come from
  a static operation specification, prefer defining the collection in a module
  attribute and passing only dynamic values when creating request headers.

      defmodule MyApi.Operation.GetItem.Header do
        alias Tesla.OpenAPI.{HeaderParam, HeaderParams}

        @header_params HeaderParams.new!([
                         HeaderParam.new!("X-Request-ID")
                       ])

        def to_headers(values) do
          HeaderParams.to_headers(@header_params, values)
        end
      end
  """

  alias Tesla.OpenAPI.HeaderParam
  alias Tesla.Param

  @enforce_keys [:definitions]
  defstruct [:definitions]

  @opaque t :: %__MODULE__{
            definitions: [HeaderParam.t()]
          }

  @spec new!([HeaderParam.t()]) :: t()
  def new!(definitions) when is_list(definitions) do
    %__MODULE__{definitions: Param.validate_definitions!(definitions, HeaderParam, :header)}
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
end
