if Code.ensure_loaded?(:telemetry) do
  defmodule Tesla.Middleware.Telemetry do
    @behaviour Tesla.Middleware

    @moduledoc """
    Emits events using the `:telemetry` library to expose instrumentation.

    ### Example usage
    ```
    defmodule MyClient do
      use Tesla

      plug Tesla.Middleware.Telemetry, prefix: [:my_client]

    end

    :telemetry.attach("my-tesla-telemetry", [:my_client, :tesla, :request, stop], fn event, measurements, meta, config ->
      # Do something with the event
    end)
    ```

    ### Options

    * `:event_prefix` - a list of atoms to prefix to the telemetry event. Defaults to `[]`

    ## Telemetry Events

    * `[:tesla, :request, :start]` - emitted at the beginning of the request.
      * Measurement: `%{time: System.monotonic_time}`
      * Metadata: `%{env: Tesla.Env.t}`

    * `[:tesla, :request, :stop]` - emitted at the end of the request.
      * Measurement: `%{duration: native_time}`
      * Metadata: `%{env: Tesla.Env.t}`

    * `[:tesla, :request, :error]` - emitted at the end of the request when there is an error.
      * Measurement: `%{duration: native_time}`
      * Metadata: `%{env: Tesla.Env.t, reason: term}`

    * `[:tesla, :request, :exception]` - emitted at the end of the request when an exception is raised.
      * Measurement: `%{duration: native_time}`
      * Metadata: `%{env: Tesla.Env.t, exception: Exception.t, stacktrace: Exception.stacktrace}`

    Please check the [telemetry](https://hexdocs.pm/telemetry/) for the further usage.
    """

    @doc false
    def call(env, next, opts) do
      prefix = Keyword.get(opts, :event_prefix, [])
      start_time = System.monotonic_time()

      emit_start(env, start_time, prefix)

      result =
        try do
          Tesla.run(env, next)
        rescue
          e ->
            stacktrace = System.stacktrace()
            metadata = %{env: env, exception: e, stacktrace: stacktrace}

            :telemetry.execute(
              prefix ++ [:tesla, :request, :exception],
              %{duration: System.monotonic_time() - start_time},
              metadata
            )

            reraise e, stacktrace
        end

      emit_stop(result, start_time, prefix, env)

      result
    end

    defp emit_start(env, start_time, prefix) do
      :telemetry.execute(prefix ++ [:tesla, :request, :start], %{time: start_time}, %{
        env: env
      })
    end

    defp emit_stop(result, start_time, prefix, req_env) do
      duration = System.monotonic_time() - start_time

      case result do
        {:ok, env} ->
          :telemetry.execute(
            prefix ++ [:tesla, :request, :stop],
            %{duration: duration},
            %{env: env}
          )

        {:error, error} ->
          :telemetry.execute(
            prefix ++ [:tesla, :request, :error],
            %{duration: duration},
            %{env: req_env, reason: error}
          )
      end

      # retained for backwards compatibility - remove in 2.0
      :telemetry.execute([:tesla, :request], %{request_time: duration}, %{result: result})
    end
  end
end
