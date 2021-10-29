defmodule Tesla.Middleware.APIKeyAuth do
  @moduledoc """
  API key authentication middleware.

  Adds a `{name, value}` tuple to headers or query params, based on `add_to` option.

  ## Examples
  ```
  defmodule MyClient do
    use Tesla
    
    # static configuration
    plug Tesla.Middleware.APIKeyAuth, add_to: :header, name: "X-API-KEY", value: "api_key"

    # dynamic API key
    def new(add_to, name, value) do
      Tesla.client [
        {Tesla.Middleware.APIKeyAuth, add_to: add_to, name: name, value: value}
      ]
    end
  end
  ```

  ## Options

  - `:add_to` - where to add an API key, either `:header` or `:query` (not set by default)
  - `:name` - API key name (defaults: "")
  - `:value` - API key value (defaults: "")
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts \\ []) do
    add_to = Keyword.fetch!(opts, :add_to)
    name = Keyword.get(opts, :name, "")
    value = Keyword.get(opts, :value, "")

    env
    |> put_api_key(add_to, [{"#{name}", "#{value}"}])
    |> Tesla.run(next)
  end

  defp put_api_key(env, add_to, api_key) do
    case add_to do
      :header -> Tesla.put_headers(env, api_key)
      :query -> Map.update!(env, :query, &(&1 ++ api_key))
    end
  end
end
