defmodule Tesla.SecretString do
  @moduledoc ~S"""
  A string that is redacted when inspected.

  Middleware options live in the client for as long as it exists, and every
  `%Tesla.Env{}` embeds its client, so a token given to a middleware would
  otherwise print wherever a client or env is inspected, including a
  `Logger.error("request failed: #{inspect(env)}")`. Wrapping the value keeps
  the redaction with the value itself, however the surrounding structure is
  inspected:

      iex> secret = Tesla.SecretString.new("Bearer s3cret")
      iex> inspect(secret)
      "#Tesla.SecretString<redacted>"
      iex> inspect([{"authorization", secret}])
      ~s([{"authorization", #Tesla.SecretString<redacted>}])
      iex> to_string(secret)
      "Bearer s3cret"

  `String.Chars` returns the value, so middleware that builds a header by
  interpolation works with a wrapped value unchanged. The flip side is that
  `"#{secret}"` prints it: interpolate a secret where it goes on the request,
  never into a log message.

  ## Examples

  ```elixir
  Tesla.client([
    {Tesla.Middleware.Headers, [{"authorization", Tesla.SecretString.new("Bearer #{token}")}]}
  ])

  Tesla.client([
    {Tesla.Middleware.BearerAuth, token: Tesla.SecretString.new(token)}
  ])

  Tesla.client([
    {Tesla.Middleware.BasicAuth, %{username: username, password: Tesla.SecretString.new(password)}}
  ])
  ```
  """

  @opaque t :: %__MODULE__{value: String.t()}

  defstruct [:value]

  @doc "Wraps `value`."
  @spec new(String.t()) :: t()
  def new(value) when is_binary(value), do: %__MODULE__{value: value}

  defimpl Inspect do
    def inspect(_secret, _opts), do: "#Tesla.SecretString<redacted>"
  end

  defimpl String.Chars do
    def to_string(secret), do: secret.value
  end
end
