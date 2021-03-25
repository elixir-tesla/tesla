defmodule Tesla.Middleware.MethodOverride do
  @moduledoc """
  Middleware that adds `X-HTTP-Method-Override` header with original request
  method and sends the request as post.

  Useful when there's an issue with sending non-POST request.

  ## Examples

  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.MethodOverride
  end
  ```

  ## Options

  - `:override` - list of HTTP methods that should be overriden, everything except `:get` and `:post` if not specified
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    if overridable?(env, opts) do
      env
      |> override
      |> Tesla.run(next)
    else
      env
      |> Tesla.run(next)
    end
  end

  defp override(env) do
    env
    |> Tesla.put_headers([{"x-http-method-override", "#{env.method}"}])
    |> Map.put(:method, :post)
  end

  defp overridable?(env, opts) do
    if opts[:override] do
      env.method in opts[:override]
    else
      not (env.method in [:get, :post])
    end
  end
end
