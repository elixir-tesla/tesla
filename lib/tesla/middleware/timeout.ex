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
  """

  @timeout_error %Tesla.Error{
    reason: :timeout,
    message: "#{__MODULE__}: Request timeout."
  }

  @default_timeout 1_000

  def call(env, next, opts) do
    opts    = opts || []
    timeout   = Keyword.get(opts, :timeout, @default_timeout)

    task = safe_async(fn -> Tesla.run(env, next) end)
    try do
      task
      |> Task.await(timeout)
      |> repass_error
    catch :exit, {:timeout, _} ->
      Process.exit(task.pid, :kill)
      raise @timeout_error
    end
  end

  defp safe_async(func) do
    Task.async(fn ->
      try do
        {:ok, func.()}
      rescue e in _ ->
        {:error, e}
      catch type, value ->
        {type, value}
      end
    end)
  end

  defp repass_error({:error, error}),
  do: raise error

  defp repass_error({:throw, value}),
  do: throw value

  defp repass_error({:exit, value}),
  do: exit value

  defp repass_error({:ok, result}),
  do: result
end
