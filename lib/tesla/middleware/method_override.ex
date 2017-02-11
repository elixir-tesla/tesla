defmodule Tesla.Middleware.MethodOverride do
  @moduledoc """
  Middleware that adds X-Http-Method-Override header with original request
  method and sends the request as post.

  Useful when there's an issue with sending non-post request.

  Available options:
  - `:override` - list of http methods that should be overriden,
  everything except get and post if not specified
  """

  def call(env, next, opts) do
    if overridable?(env, opts) do
      env
      |> override(opts)
      |> Tesla.run(next)
    else
      env
      |> Tesla.run(next)
    end
  end

  def override(env, opts) do
    env
    |> Tesla.Middleware.Headers.call([], %{"X-Http-Method-Override" => "#{env.method}"})
    |> Map.put(:method, :post)
  end

  def overridable?(env, opts) do
    if opts[:override] do
      env.method in opts[:override]
    else
      not env.method in [:get, :post]
    end
  end
end
