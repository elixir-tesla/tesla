defmodule Tesla.Middleware.PathParams do
  @moduledoc """
  Use templated URLs with provided parameters in either Phoenix style (`:id`)
  or OpenAPI style (`{id}`).

  Useful when logging or reporting metrics per URL.

  ## Parameter Values

  Parameter values may be `t:struct/0` or must implement the `Enumerable`
  protocol and produce `{key, value}` tuples when enumerated.

  ## Parameter Name Restrictions

  Phoenix style parameters may contain letters, numbers, or underscores,
  matching this regular expression:

    :[a-zA-Z][_a-zA-Z0-9]*\b

  OpenAPI style parameters may contain letters, numbers, underscores, or
  hyphens (`-`), matching this regular expression:

    \{[a-zA-Z][-_a-zA-Z0-9]*\}

  In either case, parameters that begin with underscores (`_`), hyphens (`-`),
  or numbers (`0-9`) are ignored and left as-is.

  ## Examples

  ```elixir
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.BaseUrl, "https://api.example.com"
    plug Tesla.Middleware.Logger # or some monitoring middleware
    plug Tesla.Middleware.PathParams

    def user(id) do
      params = [id: id]
      get("/users/{id}", opts: [path_params: params])
    end

    def posts(id, post_id) do
      params = [id: id, post_id: post_id]
      get("/users/:id/posts/:post_id", opts: [path_params: params])
    end
  end
  ```
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, _) do
    url = build_url(env.url, env.opts[:path_params])
    Tesla.run(%{env | url: url}, next)
  end

  @rx ~r/:([a-zA-Z][a-zA-Z0-9_]*)|[{]([a-zA-Z][-a-zA-Z0-9_]*)[}]/

  defp build_url(url, nil), do: url

  defp build_url(url, params) when is_struct(params), do: build_url(url, Map.from_struct(params))

  defp build_url(url, params) when is_map(params) or is_list(params) do
    safe_params = Map.new(params, fn {name, value} -> {to_string(name), value} end)

    Regex.replace(@rx, url, fn
      # OpenAPI matches
      match, "", name -> replace_param(safe_params, name, match)
      # Phoenix matches
      match, name, _ -> replace_param(safe_params, name, match)
    end)
  end

  defp build_url(url, _params), do: url

  defp replace_param(params, name, match) do
    case Map.fetch(params, name) do
      {:ok, nil} -> match
      :error -> match
      {:ok, value} -> URI.encode_www_form(to_string(value))
    end
  end
end
