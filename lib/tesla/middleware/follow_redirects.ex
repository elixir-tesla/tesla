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
  @redirect_statuses [301, 302, 307, 308]

  def call(env, next, opts \\ []) do
    max = Keyword.get(opts || [], :max_redirects, @max_redirects)

    redirect(env, next, max)
  end

  defp redirect(env, next, left) when left == 0 do
    case Tesla.run(env, next) do
      %{status: status} = env when not status in @redirect_statuses ->
        env
      _ ->
        raise Tesla.Error, "too many redirects"
    end
  end

  defp redirect(env, next, left) do
    case Tesla.run(env, next) do
      %{status: status, headers: %{"location" => location}} when status in @redirect_statuses ->
        location = parse_location(location, env)
        redirect(%{env | url: location}, next, left - 1)
      env ->
        env
    end
  end

  defp parse_location("/" <> _rest = location, env) do
    env.url
    |> URI.parse
    |> URI.merge(location)
    |> URI.to_string
  end

  defp parse_location(location, _env), do: location
end
