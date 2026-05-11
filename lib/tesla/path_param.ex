defmodule Tesla.PathParam do
  @moduledoc """
  A path parameter with explicit serialization settings.

  `Tesla.PathParam` is a Tesla-native value object for path parameters whose
  serialization needs to be controlled explicitly. Its serialization options
  follow the OpenAPI path parameter style semantics, while keeping the public
  API focused on the path use case.

  In `Tesla.Middleware.PathParams` `:modern` mode, wrap each path parameter
  explicitly, even when the default path serialization is enough:

      opts: [path_params: [PathParam.new!("id", 42)]]

  Pass options when a value needs non-default path serialization:

      alias Tesla.PathParam

      opts: [
        path_params: [
          PathParam.new!("coords", ["blue", "black"], style: :matrix, explode: true)
        ]
      ]

  ## Options

  `new!/3` accepts a keyword list using Elixir atoms for hand-written Tesla
  code:

    * `:style` — one of `:simple`, `:matrix`, `:label`. Defaults to `:simple`.
    * `:explode` — boolean. Defaults to `false`.
    * `:allow_reserved` — boolean. Defaults to `false`.

  [oas-style]: https://spec.openapis.org/oas/latest.html#style-values

  ## Encoding

  `Tesla.Middleware.PathParams` serializes `Tesla.PathParam` values using the
  [OpenAPI path parameter rules][oas-style] for the `simple`, `matrix`, and
  `label` styles. Serialized values are percent-encoded against the RFC 3986
  unreserved set (`A-Z`, `a-z`, `0-9`, `-`, `_`, `.`, `~`); spaces become
  `%20` (not `+`).

  With `allow_reserved: true`, path-safe reserved characters are preserved, but
  characters that would change the URL path shape, such as `/`, `?`, or `#`,
  are still percent-encoded.

  ## Object Value Ordering

  Object values may be passed as maps, structs, or keyword lists. Keyword lists
  preserve insertion order; map iteration order is intrinsic and not guaranteed
  across Elixir versions. Pass an ordered keyword list when the exact
  serialized order matters.

  ## Missing And Empty Values

  `nil` values and missing path parameters are handled by
  `Tesla.Middleware.PathParams`, which leaves unmatched placeholders untouched.
  Empty arrays and empty objects serialize according to the OpenAPI
  "undefined" column for the selected style.
  """

  @derive {Inspect, except: [:value]}
  @enforce_keys [:name, :value, :style, :explode, :allow_reserved]
  defstruct [:name, :value, :style, :explode, :allow_reserved]

  @type style :: :simple | :matrix | :label
  @opaque t :: %__MODULE__{
            name: String.t(),
            value: term(),
            style: style(),
            explode: boolean(),
            allow_reserved: boolean()
          }

  @spec new!(String.t(), term(), keyword()) :: t()
  def new!(name, value, opts \\ [])

  def new!(name, value, opts) when is_binary(name) and is_list(opts) do
    build!(opts, name, value)
  end

  def new!(name, _value, _opts) when not is_binary(name) do
    raise ArgumentError, "expected path parameter name to be a string; got #{inspect(name)}"
  end

  def new!(_name, _value, opts) do
    raise ArgumentError,
          "expected path parameter options to be a keyword list; got #{inspect(opts)}"
  end

  @doc false
  @spec encode_value(%__MODULE__{}, term()) :: String.t()
  def encode_value(%__MODULE__{allow_reserved: false}, value) do
    value |> to_string() |> URI.encode(&unreserved?/1)
  end

  def encode_value(%__MODULE__{allow_reserved: true}, value) do
    value |> to_string() |> encode_reserved_path()
  end

  defp build!(opts, name, value) do
    opts = Keyword.validate!(opts, style: :simple, explode: false, allow_reserved: false)

    %__MODULE__{
      name: name,
      value: value,
      style: opts[:style] |> validate_style!(),
      explode: validate_boolean!(:explode, opts[:explode]),
      allow_reserved: validate_boolean!(:allow_reserved, opts[:allow_reserved])
    }
  end

  defp validate_style!(style) when style in [:simple, :matrix, :label], do: style

  defp validate_style!(style) do
    raise ArgumentError,
          "unknown path parameter style #{inspect(style)}; expected :simple, :matrix, or :label"
  end

  defp validate_boolean!(_key, value) when is_boolean(value), do: value

  defp validate_boolean!(key, value) do
    raise ArgumentError, "expected #{inspect(key)} to be a boolean; got #{inspect(value)}"
  end

  defp encode_reserved_path(<<"%", h1, h2, rest::binary>>)
       when h1 in ?0..?9 or h1 in ?A..?F or h1 in ?a..?f do
    case hex?(h2) do
      true -> "%" <> <<h1, h2>> <> encode_reserved_path(rest)
      false -> "%25" <> encode_reserved_path(<<h1, h2, rest::binary>>)
    end
  end

  defp encode_reserved_path(<<c::utf8, rest::binary>>) do
    char = <<c::utf8>>

    case byte_size(char) == 1 and reserved_path_allowed?(c) do
      true -> char <> encode_reserved_path(rest)
      false -> URI.encode(char, &reserved_path_allowed?/1) <> encode_reserved_path(rest)
    end
  end

  defp encode_reserved_path("") do
    ""
  end

  defp hex?(c) when c in ?0..?9 do
    true
  end

  defp hex?(c) when c in ?A..?F do
    true
  end

  defp hex?(c) when c in ?a..?f do
    true
  end

  defp hex?(_c) do
    false
  end

  defp unreserved?(c) when c in ?A..?Z do
    true
  end

  defp unreserved?(c) when c in ?a..?z do
    true
  end

  defp unreserved?(c) when c in ?0..?9 do
    true
  end

  defp unreserved?(c) when c in [?-, ?_, ?., ?~] do
    true
  end

  defp unreserved?(_c) do
    false
  end

  defp reserved_path_allowed?(c) do
    unreserved?(c) or c in [?!, ?$, ?&, ?', ?(, ?), ?*, ?+, ?,, ?;, ?=, ?:, ?@]
  end
end
