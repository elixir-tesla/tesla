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
    Tesla.run(%{env | opts: env.opts ++ opts}, next)
  end
end
