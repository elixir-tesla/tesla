if Code.ensure_loaded?(:telemetry) do
  defmodule Tesla.Middleware.Telemetry do
    @moduledoc """
    Send the request time and meta-information through telemetry.

    ## Example usage

    ```
    defmodule MyClient do
      use Tesla

      plug Tesla.Middleware.Telemetry

    end

    :telemetry.attach("my-tesla-telemetry", [:tesla, :request], fn event, time, meta, config ->
      # Do something with the event
    end)
    ```

    Please check the [telemetry](https://hexdocs.pm/telemetry/) for the further usage.
    """

    @behaviour Tesla.Middleware

    @impl Tesla.Middleware
    def call(env, next, _opts) do
      {time, res} = :timer.tc(Tesla, :run, [env, next])
      :telemetry.execute([:tesla, :request], %{request_time: time}, %{result: res})
      res
    end
  end
end
