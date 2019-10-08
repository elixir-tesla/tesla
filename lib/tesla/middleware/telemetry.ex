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
    def call(req_env, next, opts) do
      prefix = Keyword.get(opts, :event_prefix, [])
      start_time = System.monotonic_time()

      try do
        emit_start(req_env, start_time, prefix)

        Tesla.run(req_env, next)
        |> emit_result(start_time, prefix, req_env)
      rescue
        e ->
          stacktrace = System.stacktrace()
          metadata = %{env: req_env, exception: e, stacktrace: stacktrace}

          :telemetry.execute(
            prefix ++ [:tesla, :request, :exception],
            %{duration: System.monotonic_time() - start_time},
            metadata
          )

          reraise e, stacktrace
      end
    end

    defp emit_start(req_env, start_time, prefix) do
      :telemetry.execute(prefix ++ [:tesla, :request, :start], %{time: start_time}, %{
        env: req_env
      })
    end

    defp emit_result(result, start_time, prefix, req_env) do
      try do
        result
      after
        case result do
          {:ok, env} ->
            :telemetry.execute(
              prefix ++ [:tesla, :request, :stop],
              %{duration: System.monotonic_time() - start_time},
              %{env: env}
            )

          {:error, error} ->
            :telemetry.execute(
              prefix ++ [:tesla, :request, :error],
              %{duration: System.monotonic_time() - start_time},
              %{env: req_env, reason: error}
            )
        end
      end
    end
  end
end
