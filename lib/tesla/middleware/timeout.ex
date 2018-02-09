defmodule Tesla.Middleware.Timeout do
  @behaviour Tesla.Middleware

  @moduledoc """
  Timeout http request after X seconds.

  ### Example
  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.Timeout, timeout: 2_000
  end
  ```

  ### Options
  - `:timeout` - number of milliseconds a request is allowed to take (defaults to 1000)
  """

  @default_timeout 1_000

  def call(env, next, opts) do
    opts = opts || []
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    task = safe_async(fn -> Tesla.run(env, next) end)

    try do
      task
      |> Task.await(timeout)
      |> repass_error
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, 0)
        {:error, :timeout}
    end
  end

  defp safe_async(func) do
    Task.async(fn ->
      try do
        {:ok, func.()}
      rescue
        e in _ ->
          {:exception, e}
      catch
        type, value ->
          {type, value}
      end
    end)
  end

  defp repass_error({:exception, error}), do: raise(error)

  defp repass_error({:throw, value}), do: throw(value)

  defp repass_error({:exit, value}), do: exit(value)

  defp repass_error({:ok, result}), do: result
end
