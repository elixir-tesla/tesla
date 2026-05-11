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

  alias Tesla.Param

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
  @expected_styles ":form, :space_delimited, :pipe_delimited, or :deep_object"

  @spec new!(String.t(), term(), keyword()) :: t()
  def new!(name, value, opts \\ []) do
    name = Param.validate_name!(:query, name)
    opts = Param.validate_opts!(:query, opts)
    opts = Keyword.validate!(opts, [:style, :explode, :allow_reserved])

    style =
      opts
      |> Keyword.get(:style, :form)
      |> validate_style!()

    explode = Keyword.get(opts, :explode, default_explode(style))
    allow_reserved = Keyword.get(opts, :allow_reserved, false)

    %__MODULE__{
      name: name,
      value: value,
      style: style,
      explode: Param.validate_explode!(:query, explode),
      allow_reserved: Param.validate_allow_reserved!(:query, allow_reserved)
    }
  end

  defp validate_style!(style) do
    Param.validate_style!(style, @styles, :query, @expected_styles)
  end

  @doc false
  @spec encode_name(term()) :: String.t()
  def encode_name(value) do
    Param.encode_unreserved(value)
  end

  @doc false
  @spec encode_value(%__MODULE__{}, term()) :: String.t()
  def encode_value(%__MODULE__{allow_reserved: false}, value) do
    Param.encode_unreserved(value)
  end

  def encode_value(%__MODULE__{allow_reserved: true}, value) do
    Param.encode_reserved_query(value)
  end

  defp default_explode(:form) do
    true
  end

  defp default_explode(_style) do
    false
  end
end
