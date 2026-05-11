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

  @spec new!(String.t(), term(), keyword()) :: t()
  def new!(name, value, opts \\ [])

  def new!(name, value, opts) when is_binary(name) and is_list(opts) do
    build!(opts, name, value)
  end

  def new!(name, _value, _opts) when not is_binary(name) do
    raise ArgumentError, "expected header parameter name to be a string; got #{inspect(name)}"
  end

  def new!(_name, _value, opts) do
    raise ArgumentError,
          "expected header parameter options to be a keyword list; got #{inspect(opts)}"
  end

  @spec to_header(t()) :: {String.t(), String.t()}
  def to_header(%__MODULE__{} = param) do
    {param.name, serialize(param)}
  end

  defp build!(opts, name, value) do
    opts = Keyword.validate!(opts, style: :simple, explode: false)

    %__MODULE__{
      name: name,
      value: value,
      style: opts[:style] |> validate_style!(),
      explode: validate_boolean!(:explode, opts[:explode])
    }
  end

  defp validate_style!(:simple) do
    :simple
  end

  defp validate_style!(style) do
    raise ArgumentError,
          "unknown header parameter style #{inspect(style)}; expected :simple"
  end

  defp validate_boolean!(_key, value) when is_boolean(value) do
    value
  end

  defp validate_boolean!(key, value) do
    raise ArgumentError,
          "expected header parameter #{inspect(key)} to be a boolean; got #{inspect(value)}"
  end

  defp serialize(param) do
    param
    |> classify_param()
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
    |> flatten_pairs()
    |> Enum.map_join(",", &to_string/1)
  end

  defp serialize_simple({:object, pairs}, %__MODULE__{explode: true}) do
    Enum.map_join(pairs, ",", &serialize_exploded_pair/1)
  end

  defp serialize_exploded_pair({key, value}) do
    "#{key}=#{value}"
  end

  defp flatten_pairs(pairs) do
    Enum.flat_map(pairs, &pair_values/1)
  end

  defp pair_values({key, value}) do
    [key, value]
  end

  defp classify_param(%__MODULE__{value: value}) do
    classify_value(value)
  end

  defp classify_value(nil) do
    :undefined
  end

  defp classify_value(value) when is_struct(value) do
    classify_value(Map.from_struct(value))
  end

  defp classify_value(value) when is_map(value) do
    {:object, value |> Map.to_list() |> Enum.map(&stringify_pair/1)}
  end

  defp classify_value([]) do
    {:array, []}
  end

  defp classify_value(value) when is_list(value) do
    case Enum.all?(value, &object_pair?/1) do
      true -> {:object, Enum.map(value, &stringify_pair/1)}
      false -> {:array, value}
    end
  end

  defp classify_value(value) do
    {:primitive, value}
  end

  defp stringify_pair({key, value}) do
    {to_string(key), value}
  end

  defp object_pair?({key, _value}) when is_atom(key) or is_binary(key) do
    true
  end

  defp object_pair?(_value) do
    false
  end
end
