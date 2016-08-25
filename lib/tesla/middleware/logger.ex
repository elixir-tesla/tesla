defmodule Tesla.Middleware.Logger do
  require Logger

  def call(env, run, _opts) do
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

  def call(env, run, _opts) do
    log_request(env)
    log_headers(env, "> ")
    env = %{env | body: log_body(env.body, "> ")}

    env = run.(env)

    log_response(env)
    log_headers(env, "< ")
    log_body(env.body, "< ")

    env
  end

  def log_request(env) do
    Logger.debug "> #{env.method |> to_string |> String.upcase} #{env.url}"
  end

  def log_response(env) do
    Logger.debug ""
    Logger.debug "< HTTP/1.1 #{env.status}"
  end

  def log_headers(env, prefix) do
    for {k,v} <- env.headers do
      Logger.debug "#{prefix}#{k}: #{v}"
    end
  end

  def log_body(nil, _), do: nil
  def log_body([], _), do: nil
  def log_body(%Stream{} = stream, prefix), do: log_body_stream(stream, prefix)
  def log_body(stream, prefix) when is_function(stream), do: log_body_stream(stream, prefix)
  def log_body(data, prefix) when is_binary(data) or is_list(data) do
    Logger.debug ""
    Logger.debug prefix <> to_string(data)
    data
  end

  def log_body_stream(stream, prefix) do
    Logger.debug ""
    Stream.each stream, fn line -> Logger.debug prefix <> line end
  end
end
