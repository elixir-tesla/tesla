defmodule Tesla.HeaderParam do
  @moduledoc """
  A header parameter with explicit serialization settings.

  `Tesla.HeaderParam` is a Tesla-native value object for header parameters whose
  serialization needs to be controlled explicitly. Its serialization options
  follow the OpenAPI header parameter style semantics, while keeping the public
  API focused on the header use case.

  Convert a header parameter to the raw header tuple accepted by Tesla:

      alias Tesla.HeaderParam

      HeaderParam.new!("X-Token", [12345678, 90099])
      |> HeaderParam.to_header()

  ## Options

  `new!/3` accepts a keyword list using Elixir atoms for hand-written Tesla
  code:

    * `:style` - must be `:simple`. Defaults to `:simple`.
    * `:explode` - boolean. Defaults to `false`.

  [oas-style]: https://spec.openapis.org/oas/latest.html#style-values

  ## Encoding

  `Tesla.HeaderParam.to_header/1` serializes values using the
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

  @derive {Inspect, except: [:value]}
  @enforce_keys [:name, :value, :style, :explode]
  defstruct [:name, :value, :style, :explode]

  @type style :: :simple
  @opaque t :: %__MODULE__{
            name: String.t(),
            value: term(),
            style: style(),
            explode: boolean()
          }

  @styles [:simple]
  @expected_styles ":simple"

  @spec new!(String.t(), term(), keyword()) :: t()
  def new!(name, value, opts \\ []) do
    name = Param.validate_name!(:header, name)
    opts = Param.validate_opts!(:header, opts)
    opts = Keyword.validate!(opts, style: :simple, explode: false)

    %__MODULE__{
      name: name,
      value: value,
      style: validate_style!(opts[:style]),
      explode: Param.validate_explode!(:header, opts[:explode])
    }
  end

  defp validate_style!(style) do
    Param.validate_style!(style, @styles, :header, @expected_styles)
  end

  @spec to_header(t()) :: {String.t(), String.t()}
  def to_header(%__MODULE__{} = param) do
    {param.name, serialize(param)}
  end

  defp serialize(param) do
    param
    |> value_type()
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

  defp value_type(%__MODULE__{value: value}) do
    Param.value_type(value)
  end
end
