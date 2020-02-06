defmodule Tesla.Middleware.PathParams do
  @moduledoc """
  Use templated URLs with separate params.

  Useful when logging or reporting metric per URL.

  ## Example usage

  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.BaseURl, "https://api.example.com"
    plug Tesla.Middleware.Logger # or some monitoring middleware
    plug Tesla.Middleware.PathParams

    def user(id) do
      params = [id: id]
      get("/users/:id", opts: [path_params: params])
    end
  end
  ```
  """

  @behaviour Tesla.Middleware

  @rx ~r/:([a-zA-Z]{1}[\w_]*)/

  @impl Tesla.Middleware
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
