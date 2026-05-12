defmodule Tesla.OpenAPI.QueryParam do
  @moduledoc """
  A query parameter definition with explicit serialization settings.

  `Tesla.OpenAPI.QueryParam` is a Tesla-native value object for query parameter
  metadata whose serialization needs to be controlled explicitly. Its
  serialization options follow the OpenAPI query parameter style semantics,
  while keeping the public API focused on the query use case.

  In `Tesla.Middleware.Query` `:modern` mode, define query parameters once and
  pass them through request private data with `Tesla.OpenAPI.QueryParams`:

      alias Tesla.OpenAPI.{QueryParam, QueryParams}

      query_params = QueryParams.new!([QueryParam.new!("id")])
      private = QueryParams.put_private(query_params)

      Tesla.get(client, "/items",
        query: %{"id" => 42},
        private: private
      )

  Pass options when a query value needs non-default serialization:

      alias Tesla.OpenAPI.QueryParam

      Tesla.OpenAPI.QueryParams.new!([
        QueryParam.new!("ids", style: :pipe_delimited)
      ])

  ## Options

  `new!/2` accepts a keyword list using Elixir atoms for hand-written Tesla
  code:

    * `:style` - one of `:form`, `:space_delimited`, `:pipe_delimited`, or
      `:deep_object`. Defaults to `:form`.
    * `:explode` - boolean. Defaults to `true` when the style is `:form`,
      and `false` for all other styles.
    * `:allow_reserved` - boolean. Defaults to `false`.

  [oas-style]: https://spec.openapis.org/oas/latest.html#style-values

  ## Encoding

  `Tesla.Middleware.Query` serializes values using the [OpenAPI query
  parameter rules][oas-style] for the `form`, `space_delimited`,
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

  ## OpenAPI additionalProperties

  OpenAPI `additionalProperties` belongs to the schema of an object-valued
  parameter. Model that parameter with `Tesla.OpenAPI.QueryParam` and pass the dynamic
  properties as the request value:

      query_params = Tesla.OpenAPI.QueryParams.new!([Tesla.OpenAPI.QueryParam.new!("filter")])
      query = %{"filter" => [status: "open", owner: "yordis"]}

  In `:form` style with `explode: true`, this serializes to
  `?status=open&owner=yordis`.

  ## Missing And Empty Values

  Skip a query parameter by leaving it out of `env.query`. A present `nil`
  value represents the OpenAPI "undefined" value and only has a defined
  serialization for `:form`.
  """

  alias Tesla.Param

  @enforce_keys [:name, :style, :explode, :allow_reserved]
  defstruct [:name, :style, :explode, :allow_reserved]

  @type style :: :form | :space_delimited | :pipe_delimited | :deep_object
  @opaque t :: %__MODULE__{
            name: String.t(),
            style: style(),
            explode: boolean(),
            allow_reserved: boolean()
          }

  @styles [:form, :space_delimited, :pipe_delimited, :deep_object]
  @expected_styles ":form, :space_delimited, :pipe_delimited, or :deep_object"

  @spec new!(String.t(), keyword()) :: t()
  def new!(name, opts \\ []) do
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
