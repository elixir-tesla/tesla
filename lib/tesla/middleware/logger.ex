defmodule Tesla.Middleware.Logger do
  require Logger

  def call(env, run, opts) do
    {time, env} = :timer.tc(__MODULE__, :do_call, [env, run])
    log(env, time)
    env
  end

  def do_call(env, run) do
    run.(env)
  end

  defp log(env, time) do
    ms = :io_lib.format("~.3f", [time / 10000])
    method = env.method |> to_string |> String.upcase
    message = "#{method} #{env.url} -> #{env.status} (#{ms} ms)"

    cond do
      env.status >= 400 -> Logger.error message
      env.status >= 300 -> Logger.warn message
      true              -> Logger.info message
    end
  end
end


defmodule Tesla.Middleware.DebugLogger do
  require Logger

  def call(env, run, opts) do
    log_request(env)
    log_headers(env)
    log_body(env)

    env = run.(env)

    log_response(env)
    log_headers(env)
    log_body(env)

    env
  end

  defp log_request(env) do
    Logger.debug "#{env.method |> to_string |> String.upcase} #{env.url}"
  end

  defp log_response(env) do
    Logger.debug "HTTP/1.1 #{env.status}"
  end

  defp log_headers(env) do
    for {k,v} <- env.headers do
      Logger.debug "#{k}: #{v}"
    end
  end

  defp log_body(env) do
    if env.body do
      Logger.debug ""
      Logger.debug env.body
    end
  end
end
