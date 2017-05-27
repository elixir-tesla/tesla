defmodule Tesla.Middleware.Tuples do
  @moduledoc """
  Return :ok/:error tuples for successful HTTP transations, i.e. when the request is completed
  (no network errors etc) - but it can still be an application-level error (i.e. 404 or 500).

  **NOTE**: This middleware must be included as the first in the stack (before other middleware)

  ## Example usage

      defmodule MyClient do
        use Tesla

        plug Tesla.Middleware.Tuples
        plug Tesla.Middleware.Json
      end
  """
  def call(env, next, _opts) do
    {:ok, Tesla.run(env, next)}
  rescue
    ex in Tesla.Error -> {:error, ex}
  end
end
