defmodule Tesla.Middleware.PathParams do
  @moduledoc """
  Use templated URLs with provided parameters in either Phoenix style (`:id`)
  or OpenAPI style (`{id}`).

  Useful when logging or reporting metrics per URL.

  ## Parameter Values

  Parameter values may be `t:struct/0` or must implement the `Enumerable`
  protocol and produce `{key, value}` tuples when enumerated.

  By default, this middleware preserves legacy string substitution. Pass
  `mode: :modern` to read `Tesla.OpenAPI.PathParams` definitions from request private
  data and use their explicit serialization settings.

  ## Precompiled OpenAPI Path Templates

  Generated clients can precompile OpenAPI Path Templating strings with
  `Tesla.OpenAPI.PathTemplate` and pass the template through request private data.
  This keeps `env.url` as a string while letting `mode: :modern` skip parsing
  the same template on every request.

  ```elixir
  template = Tesla.OpenAPI.PathTemplate.new!("/users/{id}")
  path_params = Tesla.OpenAPI.PathParams.new!([Tesla.OpenAPI.PathParam.new!("id")])

  private =
    %{}
    |> Tesla.OpenAPI.PathTemplate.put_private(template)
    |> Tesla.OpenAPI.PathParams.put_private(path_params)

  Tesla.get(client, template.path,
    opts: [path_params: %{"id" => 42}],
    private: private
  )
  ```

  ## Parameter Name Restrictions

  Phoenix style parameters may contain letters, numbers, or underscores,
  matching this regular expression:

    :[a-zA-Z][_a-zA-Z0-9]*\b

  In legacy substitution mode, OpenAPI-style placeholders may contain letters,
  numbers, underscores, or hyphens (`-`), matching this regular expression:

    \{[a-zA-Z][-_a-zA-Z0-9]*\}

  In legacy substitution mode, parameters that begin with underscores (`_`),
  hyphens (`-`), or numbers (`0-9`) are ignored and left as-is.

  In `mode: :modern`, OpenAPI-style placeholders are matched as `{name}` where
  `name` is any non-empty value between balanced braces. When using
  `Tesla.OpenAPI.PathTemplate`, template expression names follow OpenAPI Path
  Templating syntax instead of the legacy substitution regex.

  ## Examples

  ```elixir
  defmodule MyClient do
    def client do
      Tesla.client([
        {Tesla.Middleware.BaseUrl, "https://api.example.com"},
        Tesla.Middleware.Logger,
        Tesla.Middleware.PathParams
      ])
    end

    def user(client, id) do
      params = [id: id]
      Tesla.get(client, "/users/{id}", opts: [path_params: params])
    end

    def posts(client, id, post_id) do
      params = [id: id, post_id: post_id]
      Tesla.get(client, "/users/:id/posts/:post_id", opts: [path_params: params])
    end
  end
  ```
  """

  @behaviour Tesla.Middleware

  alias Tesla.Middleware.PathParams.Modern

  @impl Tesla.Middleware
  def call(env, next, mode: :modern), do: Modern.call(env, next)

  def call(env, next, _opts) do
    url = build_url(env.url, env.opts[:path_params])
    Tesla.run(%{env | url: url}, next)
  end

  defp build_url(url, nil), do: url

  defp build_url(url, params) when is_struct(params), do: build_url(url, Map.from_struct(params))

  defp build_url(url, params) when is_map(params) or is_list(params) do
    rx = ~r/:([a-zA-Z][a-zA-Z0-9_]*)|[{]([a-zA-Z][-a-zA-Z0-9_]*)[}]/
    safe_params = Map.new(params, fn {name, value} -> {to_string(name), value} end)

    Regex.replace(rx, url, fn
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
