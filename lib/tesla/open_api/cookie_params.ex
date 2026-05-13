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

  @enforce_keys [:definitions, :by_name]
  defstruct [:definitions, :by_name]

  @opaque t :: %__MODULE__{
            definitions: [CookieParam.t()],
            by_name: %{String.t() => CookieParam.t()}
          }

  @spec new!([CookieParam.t()]) :: t()
  def new!(definitions) when is_list(definitions) do
    %__MODULE__{definitions: definitions, by_name: by_name!(definitions)}
  end

  @doc false
  @spec definitions(t()) :: [CookieParam.t()]
  def definitions(%__MODULE__{definitions: definitions}) do
    definitions
  end

  @doc false
  @spec fetch(t(), String.t()) :: {:ok, %CookieParam{}} | :error
  def fetch(%__MODULE__{by_name: by_name}, name) when is_binary(name) do
    Map.fetch(by_name, name)
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

  defp by_name!(definitions) do
    Enum.reduce(definitions, %{}, &put_by_name!/2)
  end

  defp put_by_name!(%CookieParam{name: name} = cookie_param, by_name) do
    case Map.has_key?(by_name, name) do
      true ->
        raise ArgumentError, "duplicate cookie parameter #{inspect(name)}"

      false ->
        Map.put(by_name, name, cookie_param)
    end
  end

  defp put_by_name!(value, _by_name) do
    raise ArgumentError,
          "expected cookie parameter definitions to be #{inspect(CookieParam)} structs; got #{inspect(value)}"
  end
end
