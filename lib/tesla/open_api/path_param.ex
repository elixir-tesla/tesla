defmodule Tesla.OpenAPI.PathParam do
  @moduledoc """
  A path parameter definition with explicit serialization settings.

  `Tesla.OpenAPI.PathParam` is a value object for path parameter metadata whose
  serialization needs to be controlled explicitly. Its serialization options
  follow the OpenAPI path parameter style semantics.

  In `Tesla.Middleware.PathParams` `:modern` mode, define path parameters once
  and pass them through `t:Tesla.Env.private/0` with `Tesla.OpenAPI.PathParams`:

      path_params = Tesla.OpenAPI.PathParams.new!([PathParam.new!("id")])
      private = Tesla.OpenAPI.PathParams.put_private(path_params)

      Tesla.get(client, "/items/{id}",
        opts: [path_params: %{"id" => 42}],
        private: private
      )

  Pass options when a value needs non-default path serialization:

      alias Tesla.OpenAPI.PathParam

      Tesla.OpenAPI.PathParams.new!([
        PathParam.new!("coords", style: :matrix, explode: true)
      ])

  [oas-style]: https://spec.openapis.org/oas/latest.html#style-values

  ## Encoding

  `Tesla.Middleware.PathParams` serializes values using the
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

  Path parameters are required per the OpenAPI Specification
  ([Parameter Object — `required`](https://spec.openapis.org/oas/latest.html#parameter-required)).
  `Tesla.Middleware.PathParams` raises `ArgumentError` when a placeholder's value
  is missing or `nil`. Empty arrays and empty objects serialize according to the
  OpenAPI "undefined" column for the selected style.
  """

  alias Tesla.Param

  @enforce_keys [:name, :style, :explode, :allow_reserved]
  defstruct [:name, :style, :explode, :allow_reserved]

  @type style :: :simple | :matrix | :label
  @opaque t :: %__MODULE__{
            name: String.t(),
            style: style(),
            explode: boolean(),
            allow_reserved: boolean()
          }

  @styles [:simple, :matrix, :label]
  @expected_styles ":simple, :matrix, or :label"

  @doc """
  Creates a path parameter definition.

  Path parameters are always required per the OpenAPI Specification:
  [Parameter Object — `required`](https://spec.openapis.org/oas/latest.html#parameter-required).

  Options use Elixir atoms for hand-written Tesla code:

    * `:style` — one of `:simple`, `:matrix`, `:label`. Defaults to `:simple`.
    * `:explode` — boolean. Defaults to `false`.
    * `:allow_reserved` — boolean. Defaults to `false`.
  """
  @spec new!(
          String.t(),
          style: style(),
          explode: boolean(),
          allow_reserved: boolean()
        ) :: t()
  def new!(name, opts \\ []) do
    name = Param.validate_name!(:path, name)
    opts = Param.validate_opts!(:path, opts)
    opts = Keyword.validate!(opts, style: :simple, explode: false, allow_reserved: false)

    %__MODULE__{
      name: name,
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
