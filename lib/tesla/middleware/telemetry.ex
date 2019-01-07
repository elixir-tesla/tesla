defmodule Tesla.Middleware.Telemetry do
  @behaviour Tesla.Middleware

  @moduledoc """
  """

  @doc false
  def call(env, next, opts) do
    Tesla.run(env, next)
  end
end
