defmodule Tesla.OpenAPI.CookieParam do
  @moduledoc """
  A cookie parameter with explicit serialization settings.

  `Tesla.OpenAPI.CookieParam` is a value object for cookie parameters whose
  serialization needs to be controlled explicitly. Its serialization options
  follow the OpenAPI cookie parameter style semantics, while keeping the public
  API focused on the cookie use case.

  Define cookie parameters once and apply them to request values with
  `Tesla.OpenAPI.CookieParams`:

      alias Tesla.OpenAPI.{CookieParam, CookieParams}

      cookie_params =
        CookieParams.new!([
          CookieParam.new!("session_id"),
          CookieParam.new!("theme")
        ])

      CookieParams.to_headers(cookie_params, %{
        "session_id" => "abc123",
        "theme" => "dark"
      })

  [oas-style]: https://spec.openapis.org/oas/latest.html#style-values

  ## Encoding

  `Tesla.OpenAPI.CookieParams.to_headers/2` serializes values using the
  [OpenAPI cookie parameter rules][oas-style] for the `form` and `cookie`
  styles.

  The `cookie` style follows `Cookie` header syntax by separating name-value
  pairs with `"; "`. Values are passed through unchanged after converting each
  part with `to_string/1`; URI percent-encoding is not applied.

  The `form` style follows the OpenAPI compatibility behavior for cookie
  parameters and applies URI percent-encoding by default. With
  `allow_reserved: true`, reserved characters and already-encoded percent
  triples in values are preserved.

  ## Object Value Ordering

  Object values may be passed as maps, structs, or keyword lists. Keyword lists
  preserve insertion order; map iteration order is intrinsic and not guaranteed
  across Elixir versions. Pass an ordered keyword list when the exact
  serialized order matters.
  """

  alias Tesla.Param

  @enforce_keys [:name, :style, :explode, :allow_reserved]
  defstruct [:name, :style, :explode, :allow_reserved]

  @type style :: :form | :cookie
  @opaque t :: %__MODULE__{
            name: String.t(),
            style: style(),
            explode: boolean(),
            allow_reserved: boolean()
          }

  @styles [:form, :cookie]
  @expected_styles ":form or :cookie"

  @doc """
  Creates a cookie parameter definition.

  Options use Elixir atoms for hand-written Tesla code:

    * `:style` - one of `:form` or `:cookie`. Defaults to `:form`, matching
      the OpenAPI compatibility default for cookie parameters.
    * `:explode` - boolean. Defaults to `true` when the style is `:form`,
      and `false` for all other styles.
    * `:allow_reserved` - boolean. Defaults to `false`.
  """
  @spec new!(
          String.t(),
          style: style(),
          explode: boolean(),
          allow_reserved: boolean()
        ) :: t()
  def new!(name, opts \\ []) do
    name = Param.validate_name!(:cookie, name)
    opts = Param.validate_opts!(:cookie, opts)
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
      explode: Param.validate_explode!(:cookie, explode),
      allow_reserved: Param.validate_allow_reserved!(:cookie, allow_reserved)
    }
  end

  defp validate_style!(style) do
    Param.validate_style!(style, @styles, :cookie, @expected_styles)
  end

  defp default_explode(:form) do
    true
  end

  defp default_explode(_style) do
    false
  end

  @doc false
  @spec serialize(%__MODULE__{}, term()) :: String.t()
  def serialize(%__MODULE__{style: :form} = param, value) do
    value
    |> Param.value_type()
    |> serialize_form(param)
  end

  def serialize(%__MODULE__{style: :cookie} = param, value) do
    value
    |> Param.value_type()
    |> serialize_cookie(param)
  end

  defp serialize_form(:undefined, param) do
    serialize_form_empty(param)
  end

  defp serialize_form({:primitive, value}, param) do
    serialize_form_named_value(param, value)
  end

  defp serialize_form({:array, []}, param) do
    serialize_form_empty(param)
  end

  defp serialize_form({:array, items}, %__MODULE__{explode: false} = param) do
    serialize_form_name(param) <> "=" <> join_encoded_values(items, ",", param)
  end

  defp serialize_form({:array, items}, %__MODULE__{explode: true} = param) do
    Enum.map_join(items, "&", &serialize_form_named_value(param, &1))
  end

  defp serialize_form({:object, []}, param) do
    serialize_form_empty(param)
  end

  defp serialize_form({:object, pairs}, %__MODULE__{explode: false} = param) do
    serialize_form_name(param) <>
      "=" <>
      (pairs
       |> Param.flatten_pairs()
       |> join_encoded_values(",", param))
  end

  defp serialize_form({:object, pairs}, %__MODULE__{explode: true} = param) do
    Enum.map_join(pairs, "&", &serialize_form_pair(&1, param))
  end

  defp serialize_cookie(:undefined, param) do
    serialize_cookie_empty(param)
  end

  defp serialize_cookie({:primitive, value}, param) do
    serialize_cookie_named_value(param, value)
  end

  defp serialize_cookie({:array, []}, param) do
    serialize_cookie_empty(param)
  end

  defp serialize_cookie({:array, items}, %__MODULE__{explode: false} = param) do
    param.name <> "=" <> Enum.map_join(items, ",", &to_string/1)
  end

  defp serialize_cookie({:array, items}, %__MODULE__{explode: true} = param) do
    Enum.map_join(items, "; ", &serialize_cookie_named_value(param, &1))
  end

  defp serialize_cookie({:object, []}, param) do
    serialize_cookie_empty(param)
  end

  defp serialize_cookie({:object, pairs}, %__MODULE__{explode: false} = param) do
    param.name <>
      "=" <>
      (pairs
       |> Param.flatten_pairs()
       |> Enum.map_join(",", &to_string/1))
  end

  defp serialize_cookie({:object, pairs}, %__MODULE__{explode: true}) do
    Enum.map_join(pairs, "; ", &serialize_cookie_pair/1)
  end

  defp serialize_form_empty(param) do
    serialize_form_name(param) <> "="
  end

  defp serialize_form_named_value(param, value) do
    serialize_form_name(param) <> "=" <> encode_form_value(param, value)
  end

  defp serialize_form_pair({key, value}, param) do
    Param.encode_unreserved(key) <> "=" <> encode_form_value(param, value)
  end

  defp serialize_cookie_empty(param) do
    param.name <> "="
  end

  defp serialize_cookie_named_value(param, value) do
    param.name <> "=" <> to_string(value)
  end

  defp serialize_cookie_pair({key, value}) do
    "#{key}=#{value}"
  end

  defp serialize_form_name(param) do
    Param.encode_unreserved(param.name)
  end

  defp join_encoded_values(values, separator, param) do
    Enum.map_join(values, separator, &encode_form_value(param, &1))
  end

  defp encode_form_value(%__MODULE__{allow_reserved: false}, value) do
    Param.encode_unreserved(value)
  end

  defp encode_form_value(%__MODULE__{allow_reserved: true}, value) do
    Param.encode_reserved_query(value)
  end
end
