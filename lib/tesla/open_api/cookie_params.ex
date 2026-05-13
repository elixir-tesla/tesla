defmodule Tesla.OpenAPI.CookieParams do
  @moduledoc """
  Precompiled cookie parameter definitions.

  `Tesla.OpenAPI.CookieParams` keeps static cookie parameter metadata separate
  from per-request values. Generated clients can build it once and pass only
  dynamic values when creating request headers.

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
  """

  alias Tesla.OpenAPI.CookieParam
  alias Tesla.Param

  @enforce_keys [:definitions]
  defstruct [:definitions]

  @opaque t :: %__MODULE__{
            definitions: [CookieParam.t()]
          }

  @spec new!([CookieParam.t()]) :: t()
  def new!(definitions) when is_list(definitions) do
    %__MODULE__{definitions: Param.validate_definitions!(definitions, CookieParam, :cookie)}
  end

  @spec to_headers(t(), map() | nil) :: Tesla.Env.headers()
  def to_headers(%__MODULE__{}, nil) do
    []
  end

  def to_headers(%__MODULE__{definitions: definitions}, values) when is_map(values) do
    case Enum.reduce(definitions, {[], values}, &put_cookie/2) do
      {[], _values} ->
        []

      {cookies, _values} ->
        header_value = Enum.join(Enum.reverse(cookies), "; ")
        [{"cookie", header_value}]
    end
  end

  def to_headers(%__MODULE__{}, values) do
    raise ArgumentError,
          "expected cookie parameter values to be a map; got #{inspect(values)}"
  end

  defp put_cookie(%CookieParam{name: name} = cookie_param, {cookies, values}) do
    case Map.fetch(values, name) do
      {:ok, value} ->
        {[CookieParam.serialize(cookie_param, value) | cookies], values}

      :error ->
        {cookies, values}
    end
  end
end
