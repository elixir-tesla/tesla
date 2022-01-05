defmodule Tesla.Middleware do
  @moduledoc """
  The middleware specification.

  Middleware is an extension of basic `Tesla` functionality. It is a module that must
  implement `c:Tesla.Middleware.call/3`.

  ## Middleware options

  Options can be passed to middleware in second param of `Tesla.Builder.plug/2` macro:

      plug Tesla.Middleware.BaseUrl, "https://example.com"

  or inside tuple in case of dynamic middleware (`Tesla.client/1`):

      Tesla.client([{Tesla.Middleware.BaseUrl, "https://example.com"}])

  ## Writing custom middleware

  Writing custom middleware is as simple as creating a module implementing `c:Tesla.Middleware.call/3`.

  See `c:Tesla.Middleware.call/3` for details.

  ### Examples

      defmodule MyProject.InspectHeadersMiddleware do
        @behaviour Tesla.Middleware

        @impl Tesla.Middleware
        def call(env, next, options) do
          env
          |> inspect_headers(options)
          |> Tesla.run(next)
          |> inspect_headers(options)
        end

        defp inspect_headers(env, options) do
          IO.inspect(env.headers, options)
        end
      end

  """

  @doc """
  Invoked when a request runs.

  - (optionally) read and/or writes request data
  - calls `Tesla.run/2`
  - (optionally) read and/or writes response data

  ## Arguments

  - `env` - `Tesla.Env` struct that stores request/response data
  - `next` - middlewares that should be called after current one
  - `options` - middleware options provided by user
  """
  @callback call(env :: Tesla.Env.t(), next :: Tesla.Env.stack(), options :: any) ::
              Tesla.Env.result()
end
