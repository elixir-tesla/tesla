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

defmodule Tesla.Middleware.Headers do
  @moduledoc """
  Set default headers for all requests

  ## Examples

  ```
  defmodule Myclient do
    use Tesla

    plug Tesla.Middleware.Headers, [{"user-agent", "Tesla"}]
  end
  ```
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, headers) do
    env
    |> Tesla.put_headers(headers)
    |> Tesla.run(next)
  end
end

defmodule Tesla.Middleware.Query do
  @moduledoc """
  Set default query params for all requests

  ## Examples

  ```
  defmodule Myclient do
    use Tesla

    plug Tesla.Middleware.Query, [token: "some-token"]
  end
  ```
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, query) do
    env
    |> merge(query)
    |> Tesla.run(next)
  end

  defp merge(env, nil), do: env

  defp merge(env, query) do
    Map.update!(env, :query, &(&1 ++ query))
  end
end

defmodule Tesla.Middleware.Opts do
  @moduledoc """
  Set default opts for all requests.

  ## Examples

  ```
  defmodule Myclient do
    use Tesla

    plug Tesla.Middleware.Opts, [some: "option"]
  end
  ```
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    Tesla.run(%{env | opts: env.opts ++ opts}, next)
  end
end
