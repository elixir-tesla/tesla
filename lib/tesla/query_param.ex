defmodule Tesla.QueryParam do
  @moduledoc """
  A query parameter with explicit serialization settings.

  `Tesla.QueryParam` is a Tesla-native value object for query parameters whose
  serialization needs to be controlled explicitly. Its serialization options
  follow the OpenAPI query parameter style semantics, while keeping the public
  API focused on the query use case.

  In `Tesla.Middleware.Query` `:modern` mode, wrap each query parameter
  explicitly, even when the default query serialization is enough:

      query: [QueryParam.new!("id", 42)]

  Pass options when a value needs non-default query serialization:

      alias Tesla.QueryParam

      query: [
        QueryParam.new!("ids", [1, 2, 3], style: :pipe_delimited)
      ]

  ## Options

  `new!/3` accepts a keyword list using Elixir atoms for hand-written Tesla
  code:

    * `:style` - one of `:form`, `:space_delimited`, `:pipe_delimited`, or
      `:deep_object`. Defaults to `:form`.
    * `:explode` - boolean. Defaults to `true` when the style is `:form`,
      and `false` for all other styles.
    * `:allow_reserved` - boolean. Defaults to `false`.

  [oas-style]: https://spec.openapis.org/oas/latest.html#style-values

  ## Encoding

  `Tesla.Middleware.Query` serializes `Tesla.QueryParam` values using the
  [OpenAPI query parameter rules][oas-style] for the `form`, `space_delimited`,
  `pipe_delimited`, and `deep_object` styles. Serialized names and values are
  percent-encoded against the RFC 3986 unreserved set (`A-Z`, `a-z`, `0-9`,
  `-`, `_`, `.`, `~`); spaces become `%20` (not `+`).

  With `allow_reserved: true`, reserved characters and already-encoded percent
  triples in values are preserved. Names are always encoded with the default
  query-name encoding.

  ## Object Value Ordering

  Object values may be passed as maps, structs, or keyword lists. Keyword lists
  preserve insertion order; map iteration order is intrinsic and not guaranteed
  across Elixir versions. Pass an ordered keyword list when the exact
  serialized order matters.

  ## Missing And Empty Values

  Skip a query parameter by leaving it out of `env.query`. A `nil` value
  represents the OpenAPI "undefined" value and only has a defined serialization
  for `:form`.
  """

  @derive {Inspect, except: [:value]}
  @enforce_keys [:name, :value, :style, :explode, :allow_reserved]
  defstruct [:name, :value, :style, :explode, :allow_reserved]

  @type style :: :form | :space_delimited | :pipe_delimited | :deep_object
  @opaque t :: %__MODULE__{
            name: String.t(),
            value: term(),
            style: style(),
            explode: boolean(),
            allow_reserved: boolean()
          }

  @styles [:form, :space_delimited, :pipe_delimited, :deep_object]
  @reserved ~c":/?#[]@!$&'()*+,;="

  @spec new!(String.t(), term(), keyword()) :: t()
  def new!(name, value, opts \\ [])

  def new!(name, value, opts) when is_binary(name) and is_list(opts) do
    build!(opts, name, value)
  end

  def new!(name, _value, _opts) when not is_binary(name) do
    raise ArgumentError, "expected query parameter name to be a string; got #{inspect(name)}"
  end

  def new!(_name, _value, opts) do
    raise ArgumentError,
          "expected query parameter options to be a keyword list; got #{inspect(opts)}"
  end

  @doc false
  @spec encode_name(term()) :: String.t()
  def encode_name(value) do
    value
    |> to_string()
    |> URI.encode(&unreserved?/1)
  end

  @doc false
  @spec encode_value(%__MODULE__{}, term()) :: String.t()
  def encode_value(%__MODULE__{allow_reserved: false}, value) do
    value
    |> to_string()
    |> URI.encode(&unreserved?/1)
  end

  def encode_value(%__MODULE__{allow_reserved: true}, value) do
    value
    |> to_string()
    |> encode_reserved()
  end

  defp build!(opts, name, value) do
    opts = Keyword.validate!(opts, [:style, :explode, :allow_reserved])
    style = opts |> Keyword.get(:style, :form) |> validate_style!()

    %__MODULE__{
      name: name,
      value: value,
      style: style,
      explode:
        opts |> Keyword.get(:explode, default_explode(style)) |> validate_boolean!(:explode),
      allow_reserved:
        opts |> Keyword.get(:allow_reserved, false) |> validate_boolean!(:allow_reserved)
    }
  end

  defp validate_style!(style) when style in @styles do
    style
  end

  defp validate_style!(style) do
    raise ArgumentError,
          "unknown query parameter style #{inspect(style)}; expected :form, :space_delimited, :pipe_delimited, or :deep_object"
  end

  defp validate_boolean!(value, _key) when is_boolean(value) do
    value
  end

  defp validate_boolean!(value, key) do
    raise ArgumentError,
          "expected query parameter #{inspect(key)} to be a boolean; got #{inspect(value)}"
  end

  defp default_explode(:form) do
    true
  end

  defp default_explode(_style) do
    false
  end

  defp encode_reserved(<<>>) do
    ""
  end

  defp encode_reserved(<<"%", high, low, rest::binary>>) do
    case hex_digit?(high) and hex_digit?(low) do
      true ->
        "%" <> <<high, low>> <> encode_reserved(rest)

      false ->
        "%25" <> encode_reserved(<<high, low, rest::binary>>)
    end
  end

  defp encode_reserved(<<"%", rest::binary>>) do
    "%25" <> encode_reserved(rest)
  end

  defp encode_reserved(<<byte, rest::binary>>) do
    case unreserved_or_reserved?(byte) do
      true ->
        <<byte>> <> encode_reserved(rest)

      false ->
        percent_encode_byte(byte) <> encode_reserved(rest)
    end
  end

  defp percent_encode_byte(byte) do
    "%" <> Base.encode16(<<byte>>)
  end

  defp hex_digit?(byte) when byte in ?0..?9 do
    true
  end

  defp hex_digit?(byte) when byte in ?A..?F do
    true
  end

  defp hex_digit?(byte) when byte in ?a..?f do
    true
  end

  defp hex_digit?(_byte) do
    false
  end

  defp unreserved_or_reserved?(byte) do
    unreserved?(byte) or byte in @reserved
  end

  defp unreserved?(byte) when byte in ?A..?Z do
    true
  end

  defp unreserved?(byte) when byte in ?a..?z do
    true
  end

  defp unreserved?(byte) when byte in ?0..?9 do
    true
  end

  defp unreserved?(byte) when byte in [?-, ?_, ?., ?~] do
    true
  end

  defp unreserved?(_byte) do
    false
  end
end
