if Code.ensure_loaded?(:telemetry) do
  defmodule Tesla.Middleware.Telemetry do
    @moduledoc """
    Emits events using the `:telemetry` library to expose instrumentation.

    ## Example usage

    ```
    defmodule MyClient do
      use Tesla

      plug Tesla.Middleware.Telemetry

    end

    :telemetry.attach("my-tesla-telemetry", [:tesla, :request, stop], fn event, measurements, meta, config ->
      # Do something with the event
    end)
    ```

    ## Options

    * `:event_prefix` - a list of atoms to prefix to the telemetry event name. This can be set if you need to distinguish events from different clients. Defaults to `[]`

    ## Telemetry Events

    * `[:tesla, :request, :start]` - emitted at the beginning of the request.
      * Measurement: `%{time: System.monotonic_time}`
      * Metadata: `%{env: Tesla.Env.t}`

    * `[:tesla, :request, :stop]` - emitted at the end of the request.
      * Measurement: `%{duration: native_time}`
      * Metadata: `%{env: Tesla.Env.t}`

    * `[:tesla, :request, :error]` - emitted when there is an error.
      * Measurement: `%{value: 1}`
      * Metadata: `%{env: Tesla.Env.t, kind: Exception.kind | nil, reason: term, stacktrace: Exception.stacktrace}`

    ## Legacy Telemetry Events

      * `[:tesla, :request]` - This event is emitted for backwards compatibility only and should be considered deprecated.
      This event can be disabled by setting `config :tesla, Tesla.Middleware.Telemetry, disable_legacy_event: true` in your config. Be sure to run `mix deps.compile --force tesla` after changing this setting to ensure the change is picked up.

    Please check the [telemetry](https://hexdocs.pm/telemetry/) for the further usage.
    """

    @disable_legacy_event Application.get_env(:tesla, Tesla.Middleware.Telemetry,
                            disable_legacy_event: false
                          )[:disable_legacy_event]

    @behaviour Tesla.Middleware

    @impl Tesla.Middleware
    def call(env, next, opts) do
      prefix = Keyword.get(opts, :event_prefix, [])
      start_time = System.monotonic_time()

      emit_start(env, start_time, prefix)

      try do
        Tesla.run(env, next)
      catch
        kind, reason ->
          stacktrace = System.stacktrace()
          metadata = %{env: env, kind: kind, reason: reason, stacktrace: stacktrace}

          :telemetry.execute(
            prefix ++ [:tesla, :request, :error],
            %{value: 1},
            metadata
          )

          emit_stop(env, start_time, prefix, {:error, reason})

          :erlang.raise(kind, reason, stacktrace)
      else
        {:ok, env} = result ->
          emit_stop(env, start_time, prefix, result)
          result

        {:error, error} = result ->
          :telemetry.execute(
            prefix ++ [:tesla, :request, :error],
            %{value: 1},
            %{env: env, kind: nil, reason: error, stacktrace: []}
          )

          emit_stop(env, start_time, prefix, result)
          result
      end
    end

    defp emit_start(env, start_time, prefix) do
      :telemetry.execute(prefix ++ [:tesla, :request, :start], %{time: start_time}, %{
        env: env
      })
    end

    defp emit_stop(env, start_time, prefix, result) do
      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        prefix ++ [:tesla, :request, :stop],
        %{duration: duration},
        %{env: env}
      )

      if !@disable_legacy_event do
        # retained for backwards compatibility - remove in 2.0
        :telemetry.execute([:tesla, :request], %{request_time: duration}, %{result: result})
      end
    end
  end
end
