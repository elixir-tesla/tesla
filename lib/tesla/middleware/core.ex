defmodule Tesla.Middleware.BaseUrl do
  @behaviour Tesla.Middleware

  @moduledoc """
  Set base URL for all requests.

  The base URL will be prepended to request path/url only
  if it does not include http(s).

  ### Example usage
  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.BaseUrl, "https://api.github.com"
  end

  MyClient.get("/path") # equals to GET https://api.github.com/path
  MyClient.get("http://example.com/path") # equals to GET http://example.com/path
  ```
  """

  def call(env, next, base) do
    env
    |> apply_base(base)
    |> Tesla.run(next)
  end

  defp apply_base(env, base) do
    if Regex.match?(~r/^https?:\/\//, env.url) do
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
      {_, "/" <> rest} -> base <> "/" <> rest
      {_, rest} -> base <> "/" <> rest
    end
  end
end

defmodule Tesla.Middleware.Headers do
  @behaviour Tesla.Middleware

  @moduledoc """
  Set default headers for all requests

  ### Example usage
  ```
  defmodule Myclient do
    use Tesla

    plug Tesla.Middleware.Headers, [{"user-agent", "Tesla"}]
  end
  ```
  """
  def call(env, next, headers) do
    env
    |> Tesla.put_headers(headers)
    |> Tesla.run(next)
  end
end

defmodule Tesla.Middleware.Query do
  @behaviour Tesla.Middleware

  @moduledoc """
  Set default query params for all requests

  ### Example usage
  ```
  defmodule Myclient do
    use Tesla

    plug Tesla.Middleware.Query, [token: "some-token"]
  end
  ```
  """
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
  @behaviour Tesla.Middleware

  @moduledoc """
  Set default opts for all requests

  ### Example usage
  ```
  defmodule Myclient do
    use Tesla

    plug Tesla.Middleware.Opts, [some: "option"]
  end
  ```
  """
  def call(env, next, opts) do
    Tesla.run(%{env | opts: env.opts ++ opts}, next)
  end
end
