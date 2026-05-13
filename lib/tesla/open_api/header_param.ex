defmodule Tesla.OpenAPI.HeaderParam do
  @moduledoc """
  A header parameter with explicit serialization settings.

  `Tesla.OpenAPI.HeaderParam` is a value object for header parameters whose
  serialization needs to be controlled explicitly. Its serialization options
  follow the OpenAPI header parameter style semantics, while keeping the public
  API focused on the header use case.

  Define header parameters once and apply them to request values with
  `Tesla.OpenAPI.HeaderParams`:

      alias Tesla.OpenAPI.{HeaderParam, HeaderParams}

      header_params =
        HeaderParams.new!([
          HeaderParam.new!("X-Token")
        ])

      HeaderParams.to_headers(header_params, %{"X-Token" => [12345678, 90099]})

  [oas-style]: https://spec.openapis.org/oas/latest.html#style-values

  ## Encoding

  `Tesla.OpenAPI.HeaderParams.to_headers/2` serializes values using the
  [OpenAPI header parameter rules][oas-style] for the `simple` style. Header
  values are passed through unchanged after converting each part with
  `to_string/1`; URI percent-encoding is not applied.

  ## Object Value Ordering

  Object values may be passed as maps, structs, or keyword lists. Keyword lists
  preserve insertion order; map iteration order is intrinsic and not guaranteed
  across Elixir versions. Pass an ordered keyword list when the exact
  serialized order matters.
  """

  alias Tesla.Param

  @enforce_keys [:name, :style, :explode]
  defstruct [:name, :style, :explode]

  @type style :: :simple
  @opaque t :: %__MODULE__{
            name: String.t(),
            style: style(),
            explode: boolean()
          }

  @styles [:simple]
  @expected_styles ":simple"

  @doc """
  Creates a header parameter definition.

  Options use Elixir atoms for hand-written Tesla code:

    * `:style` - must be `:simple`. Defaults to `:simple`.
    * `:explode` - boolean. Defaults to `false`.
  """
  @spec new!(
          String.t(),
          style: style(),
          explode: boolean()
        ) :: t()
  def new!(name, opts \\ []) do
    name = Param.validate_name!(:header, name)
    opts = Param.validate_opts!(:header, opts)
    opts = Keyword.validate!(opts, style: :simple, explode: false)

    %__MODULE__{
      name: name,
      style: validate_style!(opts[:style]),
      explode: Param.validate_explode!(:header, opts[:explode])
    }
  end

  defp validate_style!(style) do
    Param.validate_style!(style, @styles, :header, @expected_styles)
  end

  @doc false
  @spec serialize(%__MODULE__{}, term()) :: String.t()
  def serialize(%__MODULE__{} = param, value) do
    value
    |> Param.value_type()
    |> serialize_simple(param)
  end

  defp serialize_simple(:undefined, _param) do
    ""
  end

  defp serialize_simple({:primitive, value}, _param) do
    to_string(value)
  end

  defp serialize_simple({:array, items}, _param) do
    Enum.map_join(items, ",", &to_string/1)
  end

  defp serialize_simple({:object, pairs}, %__MODULE__{explode: false}) do
    pairs
    |> Param.flatten_pairs()
    |> Enum.map_join(",", &to_string/1)
  end

  defp serialize_simple({:object, pairs}, %__MODULE__{explode: true}) do
    Enum.map_join(pairs, ",", &serialize_exploded_pair/1)
  end

  defp serialize_exploded_pair({key, value}) do
    "#{key}=#{value}"
  end
end
