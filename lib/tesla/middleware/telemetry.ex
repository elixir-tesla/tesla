defmodule Tesla.Middleware.Telemetry do
  @behaviour Tesla.Middleware

  @moduledoc """
  Send the request duration and meta-information through telemetry.

  ### Example usage
  ```
  defmodule TelemetryHandler do
    use GenServer

    def start_link(_, _) do
      :telemetry_app.start(nil, nil)
      :telemetry.attach(
        "tesla-telemetry",
        [:tesla, :telemetry, :traffic],
        fn ([:tesla, :telemetry, :traffic], time, meta, _config) -> # Do sth end,
        nil)
    end
  end

  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.Telemetry

  end
  ```
  """

  @doc false
  def call(env, next, _opts) do
    {time, res} = :timer.tc(Tesla, :run, [env, next])
    :telemetry.execute([:tesla, :telemetry, :traffic], time, Enum.into([res], %{}))
    res
  end
end
