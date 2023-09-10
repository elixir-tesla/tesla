defmodule Tesla.Middleware.BaseUrl do
  @moduledoc """
  Set base URL for all requests.

  The base URL will be prepended to request path/URL only
  if it does not include http(s).

  ## Examples

  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.BaseUrl, "https://example.com/foo"
  end

  MyClient.get("/path") # equals to GET https://example.com/foo/path
  MyClient.get("path") # equals to GET https://example.com/foo/path
  MyClient.get("") # equals to GET https://example.com/foo
  MyClient.get("http://example.com/bar") # equals to GET http://example.com/bar
  ```
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, base) do
    env
    |> apply_base(base)
    |> Tesla.run(next)
  end

  defp apply_base(env, base) do
    if Regex.match?(~r/^https?:\/\//i, env.url) do
      # skip if url is already with scheme
      env
    else
      %{env | url: join(base, env.url)}
    end
  end

  defp join(base, url) do
    case {String.last(to_string(base)), url} do
      {nil, url} -> url
      {"/", "/" <> rest} -> base <> rest
      {"/", rest} -> base <> rest
      {_, ""} -> base
      {_, "/" <> rest} -> base <> "/" <> rest
      {_, rest} -> base <> "/" <> rest
    end
  end
end
