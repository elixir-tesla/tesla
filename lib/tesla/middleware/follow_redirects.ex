defmodule Tesla.Middleware.FollowRedirects do
  @doc """
  Follow 301/302 redirects

  Example:

  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.FollowRedirects, max_redirects: 3 # defaults to 5
  end
  """
  @max_redirects 5
  @redirect_statuses [301, 302, 307, 308]

  def call(env, next, opts \\ []) do
    max = Keyword.get(opts || [], :max_redirects, @max_redirects)

    redirect(env, next, max)
  end

  defp redirect(_env, _next, left) when left <= 0 do
    raise Tesla.Error, "too many redirects"
  end

  defp redirect(env, next, left) do
    case Tesla.run(env, next) do
      %{status: status, headers: %{"location" => location}} when status in @redirect_statuses ->
        redirect(%{env | url: location}, next, left - 1)
      env ->
        env
    end
  end
end
