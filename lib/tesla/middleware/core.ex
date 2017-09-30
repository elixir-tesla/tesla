defmodule Tesla.Middleware.Normalize do
  @moduledoc false
  def call(env, next, _opts) do
    env
    |> normalize
    |> Tesla.run(next)
    |> normalize
  end

  def normalize({:error, reason}) do
    raise %Tesla.Error{message: "adapter error: #{inspect reason}", reason: reason}
  end
  def normalize(env) do
    env
    |> Map.update!(:status,   &normalize_status/1)
    |> Map.update!(:headers,  &normalize_headers/1)
    |> Map.update!(:body,     &normalize_body/1)
  end

  def normalize_status(nil), do: nil
  def normalize_status(status) when is_integer(status), do: status
  def normalize_status(status) when is_binary(status),  do: status |> String.to_integer
  def normalize_status(status) when is_list(status),    do: status |> to_string |> String.to_integer

  def normalize_headers(headers) when is_map(headers) or is_list(headers) do
    Enum.into headers, %{}, fn {k,v} ->
      {k |> to_string |> String.downcase, v |> to_string}
    end
  end

  def normalize_body(data) when is_list(data), do: IO.iodata_to_binary(data)
  def normalize_body(data), do: data
end


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
      env # skip if url is already with scheme
    else
      %{env | url: join(base, env.url)}
    end
  end

  defp join(base, url) do
    case {String.last(to_string(base)), url} do
      {nil, url}          -> url
      {"/", "/" <> rest}  -> base <> rest
      {"/", rest}         -> base <> rest
      {_,   "/" <> rest}  -> base <> "/" <> rest
      {_,   rest}         -> base <> "/" <> rest
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

    plug Tesla.Middleware.Headers, %{"User-Agent" => "Tesla"}
  end
  ```
  """
  def call(env, next, headers) do
    env
    |> merge(headers)
    |> Tesla.run(next)
  end

  defp merge(env, nil), do: env
  defp merge(env, headers) do
    Map.update!(env, :headers, &Map.merge(&1, headers))
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
    Map.update!(env, :query, & &1 ++ query)
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


defmodule Tesla.Middleware.BaseUrlFromConfig do
  def call(env, next, opts) do
    base = config(opts)[:base_url]
    Tesla.Middleware.BaseUrl.call(env, next, base)
  end

  defp config(opts) do
    Application.get_env(Keyword.fetch!(opts, :otp_app), Keyword.fetch!(opts, :module))
  end
end
