if Code.ensure_loaded?(:opentelemetry_process_propagator) do
  defmodule Tesla.Middleware.OpentelemetryTimeout do
    @moduledoc """
    Timeout HTTP request after X milliseconds.

    This module differentiates from Tesla.Middleware.Timeout
    in the sense it propagates the Opentelemetry context from parent to
    child process.

    ## Examples

    ```
    defmodule MyClient do
      use Tesla

      plug Tesla.Middleware.OpentelemetryTimeout, timeout: 2_000
    end
    ```

    ## Options

    - `:timeout` - number of milliseconds a request is allowed to take (defaults to `1000`)
    """

    @behaviour Tesla.Middleware

    @default_timeout 1_000

    @impl Tesla.Middleware
    def call(env, next, opts) do
      opts = opts || []
      timeout = Keyword.get(opts, :timeout, @default_timeout)

      task = safe_async(fn -> Tesla.run(env, next) end)

      try do
        task
        |> OpentelemetryProcessPropagator.Task.await(timeout)
        |> repass_error
      catch
        :exit, {:timeout, _} ->
          OpentelemetryProcessPropagator.Task.shutdown(task, 0)
          {:error, :timeout}
      end
    end

    defp safe_async(func) do
      OpentelemetryProcessPropagator.Task.async(fn ->
        try do
          {:ok, func.()}
        rescue
          e in _ ->
            {:exception, e, __STACKTRACE__}
        catch
          type, value ->
            {type, value}
        end
      end)
    end

    defp repass_error({:exception, error, stacktrace}), do: reraise(error, stacktrace)

    defp repass_error({:throw, value}), do: throw(value)

    defp repass_error({:exit, value}), do: exit(value)

    defp repass_error({:ok, result}), do: result
  end
end
