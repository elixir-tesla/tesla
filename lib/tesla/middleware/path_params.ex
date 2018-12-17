defmodule Tesla.Middleware.PathParams do
  @behaviour Tesla.Middleware

  @impl true
  def call(env, next, _) do
    url = build_url(env.url, env.opts[:path_params])
    Tesla.run(%{env | url: url}, next)
  end

  defp build_url(url, nil), do: url

  defp build_url(url, params),
    do: Enum.reduce(params, url, fn {k, v}, u -> String.replace(u, ":#{k}", to_string(v)) end)
end
