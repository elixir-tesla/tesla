defmodule Tesla.Middleware.Telemetry do
  @behaviour Tesla.Middleware

  @moduledoc """
  """

  @doc false
  def call(env, next, _opts) do
    {time, res} = :timer.tc(Tesla, :run, [env, next])
    :telemetry.execute([:tesla, :telemetry, :traffic], time, Enum.into([res], %{}))
    res
  end
end
