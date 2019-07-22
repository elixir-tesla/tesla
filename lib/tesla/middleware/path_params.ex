defmodule Tesla.Middleware.PathParams do
  @behaviour Tesla.Middleware

  @rx ~r/:([\w_]+)/

  @impl true
  def call(env, next, _) do
    url = build_url(env.url, env.opts[:path_params])
    Tesla.run(%{env | url: url}, next)
  end

  defp build_url(url, nil), do: url

  defp build_url(url, params) do
    Regex.replace(@rx, url, fn match, key ->
      to_string(params[String.to_existing_atom(key)] || match)
    end)
  end
end
