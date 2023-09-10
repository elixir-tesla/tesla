defmodule Tesla.Middleware.Timeout do
  @moduledoc """
  Timeout HTTP request after X milliseconds.

  ## Examples

      defmodule MyClient do
        use Tesla

        plug Tesla.Middleware.Timeout, timeout: 2_000
      end

  If you are using OpenTelemetry in your project, you may be interested in
  using `OpentelemetryProcessPropagator.Task` to have a better integration using
  the `task_module` option.

      defmodule MyClient do
        use Tesla

        plug Tesla.Middleware.Timeout,
          timeout: 2_000,
          task_module: OpentelemetryProcessPropagator.Task
      end

  ## Options

  - `:timeout` - number of milliseconds a request is allowed to take (defaults to `1000`)
  - `:task_module` - the `Task` module used to spawn tasks. Useful when you want
    use alternatives such as `OpentelemetryProcessPropagator.Task` from OTEL
    project.
  """

  @behaviour Tesla.Middleware

  @default_timeout 1_000

  @impl Tesla.Middleware
  def call(env, next, opts) do
    opts = opts || []
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    task_module = Keyword.get(opts, :task_module, Task)

    task = safe_async(task_module, fn -> Tesla.run(env, next) end)

    try do
      task
      |> task_module.await(timeout)
      |> repass_error
    catch
      :exit, {:timeout, _} ->
        task_module.shutdown(task, 0)
        {:error, :timeout}
    end
  end

  defp safe_async(task_module, func) do
    task_module.async(fn ->
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
