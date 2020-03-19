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

    :telemetry.attach("my-tesla-telemetry", [:tesla, :request, :stop], fn event, measurements, meta, config ->
      # Do something with the event
    end)
    ```

    ## Telemetry Events

    * `[:tesla, :request, :start]` - emitted at the beginning of the request.
      * Measurement: `%{system_time: System.system_time()}`
      * Metadata: `%{env: Tesla.Env.t()}`

    * `[:tesla, :request, :stop]` - emitted at the end of the request.
      * Measurement: `%{duration: native_time}`
      * Metadata: `%{env: Tesla.Env.t()} | %{env: Tesla.Env.t(), error: term()}`

    * `[:tesla, :request, :exception]` - emitted when an exception has been raised.
      * Measurement: `%{duration: native_time}`
      * Metadata: `%{kind: Exception.kind(), reason: term(), stacktrace: Exception.stacktrace()}`

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
    def call(env, next, _opts) do
      start_time = System.monotonic_time()

      emit_start(%{env: env})

      try do
        Tesla.run(env, next)
      catch
        kind, reason ->
          stacktrace = System.stacktrace()
          duration = System.monotonic_time() - start_time

          emit_exception(duration, %{kind: kind, reason: reason, stacktrace: stacktrace})

          :erlang.raise(kind, reason, stacktrace)
      else
        {:ok, env} = result ->
          duration = System.monotonic_time() - start_time

          emit_stop(duration, %{env: env})
          emit_legacy_event(duration, result)

          result

        {:error, reason} = result ->
          duration = System.monotonic_time() - start_time

          emit_stop(duration, %{env: env, error: reason})
          emit_legacy_event(duration, result)

          result
      end
    end

    defp emit_start(metadata) do
      :telemetry.execute(
        [:tesla, :request, :start],
        %{system_time: System.system_time()},
        metadata
      )
    end

    defp emit_stop(duration, metadata) do
      :telemetry.execute(
        [:tesla, :request, :stop],
        %{duration: duration},
        metadata
      )
    end

    defp emit_legacy_event(duration, result) do
      if !@disable_legacy_event do
        :telemetry.execute(
          [:tesla, :request],
          %{request_time: duration},
          %{result: result}
        )
      end
    end

    defp emit_exception(duration, metadata) do
      :telemetry.execute(
        [:tesla, :request, :exception],
        %{duration: duration},
        metadata
      )
    end
  end
end
