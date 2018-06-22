defmodule Tesla.Middleware.FollowRedirects do
  @behaviour Tesla.Middleware

  @moduledoc """
  Follow 3xx redirects

  ### Example
  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.FollowRedirects, max_redirects: 3 # defaults to 5
  end
  ```

  ### Options
  - `:max_redirects` - limit number of redirects (default: `5`)

  """

  @max_redirects 5
  @redirect_statuses [301, 302, 303, 307, 308]

  def call(env, next, opts \\ []) do
    max = Keyword.get(opts || [], :max_redirects, @max_redirects)

    redirect(env, next, max)
  end

  defp redirect(env, next, left) when left == 0 do
    case Tesla.run(env, next) do
      {:ok, %{status: status} = env} when not (status in @redirect_statuses) ->
        {:ok, env}

      {:ok, _env} ->
        {:error, {__MODULE__, :too_many_redirects}}

      error ->
        error
    end
  end

  defp redirect(env, next, left) do
    case Tesla.run(env, next) do
      {:ok, %{status: status} = res} when status in @redirect_statuses ->
        case Tesla.get_header(res, "location") do
          nil ->
            {:ok, res}

          location ->
            location = parse_location(location, res)

            %{env | status: res.status}
            |> new_request(location)
            |> redirect(next, left - 1)
        end

      other ->
        other
    end
  end

  # The 303 (See Other) redirect was added in HTTP/1.1 to indicate that the originally
  # requested resource is not available, however a related resource (or another redirect)
  # available via GET is available at the specified location.
  # https://tools.ietf.org/html/rfc7231#section-6.4.4
  defp new_request(%{status: 303} = env, location), do: %{env | url: location, method: :get}
  defp new_request(env, location), do: %{env | url: location}

  defp parse_location("/" <> _rest = location, env) do
    env.url
    |> URI.parse()
    |> URI.merge(location)
    |> URI.to_string()
  end

  defp parse_location(location, _env), do: location
end
