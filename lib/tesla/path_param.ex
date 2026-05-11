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

  alias Tesla.Param

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

  @styles [:simple, :matrix, :label]
  @expected_styles ":simple, :matrix, or :label"

  @spec new!(String.t(), term(), keyword()) :: t()
  def new!(name, value, opts \\ []) do
    name = Param.validate_name!(:path, name)
    opts = Param.validate_opts!(:path, opts)
    opts = Keyword.validate!(opts, style: :simple, explode: false, allow_reserved: false)

    %__MODULE__{
      name: name,
      value: value,
      style: validate_style!(opts[:style]),
      explode: Param.validate_explode!(:path, opts[:explode]),
      allow_reserved: Param.validate_allow_reserved!(:path, opts[:allow_reserved])
    }
  end

  defp validate_style!(style) do
    Param.validate_style!(style, @styles, :path, @expected_styles)
  end

  @doc false
  @spec encode_value(%__MODULE__{}, term()) :: String.t()
  def encode_value(%__MODULE__{allow_reserved: false}, value) do
    Param.encode_unreserved(value)
  end

  def encode_value(%__MODULE__{allow_reserved: true}, value) do
    Param.encode_reserved_path(value)
  end
end
