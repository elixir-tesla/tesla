defmodule Tesla.Middleware.Opts do
  @moduledoc """
  Set default opts for all requests.

  ## Examples

  ```
  defmodule Myclient do
    use Tesla

    plug Tesla.Middleware.Opts, [some: "option"]
  end
  ```
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    adapter =
      env.opts
      |> Keyword.get(:adapter, [])
      |> Keyword.merge(opts[:adapter] || [])

    opts =
      env.opts
      |> Keyword.merge(opts)
      |> Keyword.put(:adapter, adapter)

    Tesla.run(%{env | opts: opts}, next)
  end
end
