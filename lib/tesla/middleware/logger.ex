defmodule Tesla.Middleware.Logger do
  require Logger

  def call(env, next, _opts) do
    {time, env} = :timer.tc(Tesla, :run, [env, next])
    _ = log(env, time)
    env
  rescue
    ex in Tesla.Error ->
      stacktrace = System.stacktrace()
      _ = log(env, ex)
      reraise ex, stacktrace
  end

  defp log(env, %Tesla.Error{message: message}) do
    Logger.error "#{normalize_method(env)} #{env.url} -> #{message}"
  end

  defp log(env, time) do
    ms = :io_lib.format("~.3f", [time / 1000])
    message = "#{normalize_method(env)} #{env.url} -> #{env.status} (#{ms} ms)"

    cond do
      env.status >= 400 -> Logger.error message
      env.status >= 300 -> Logger.warn message
      true              -> Logger.info message
    end
  end

  defp normalize_method(env) do
    env.method |> to_string() |> String.upcase()
  end
end


defmodule Tesla.Middleware.DebugLogger do
  require Logger

  def call(env, next, _opts) do
    env
    |> log_request
    |> log_headers("> ")
    |> log_params("> ")
    |> log_body("> ")
    |> Tesla.run(next)
    |> log_response
    |> log_headers("< ")
    |> log_body("< ")
  rescue
    ex in Tesla.Error ->
      stacktrace = System.stacktrace()
      _ = log_exception(ex, "< ")
      reraise ex, stacktrace
  end

  def log_request(env) do
    _ = Logger.debug "> #{env.method |> to_string |> String.upcase} #{env.url}"
    env
  end

  def log_response(env) do
    _ = Logger.debug ""
    _ = Logger.debug "< HTTP/1.1 #{env.status}"
    env
  end

  def log_headers(env, prefix) do
    for {k,v} <- env.headers do
      _ = Logger.debug "#{prefix}#{k}: #{v}"
    end
    env
  end

  def log_params(env, prefix) do
    for {k,v} <- env.query do
      _ = Logger.debug "#{prefix} Query Param '#{k}': '#{v}'"
    end
    env
  end

  def log_body(%Tesla.Env{} = env, _prefix) do
    Map.update!(env, :body, & log_body(&1, "> "))
  end
  def log_body(nil, _), do: nil
  def log_body([], _), do: nil
  def log_body(%Stream{} = stream, prefix), do: log_body_stream(stream, prefix)
  def log_body(stream, prefix) when is_function(stream), do: log_body_stream(stream, prefix)
  def log_body(data, prefix) when is_binary(data) or is_list(data) do
    _ = Logger.debug ""
    _ = Logger.debug prefix <> to_string(data)
    data
  end
  def log_body(data, prefix) when is_map(data) do
    _ = Logger.debug ""
    _ = Logger.debug "#{prefix} #{inspect data}"
    data
  end

  def log_body_stream(stream, prefix) do
    _ = Logger.debug ""
    Stream.each stream, fn line -> Logger.debug prefix <> line end
  end

  defp log_exception(%Tesla.Error{message: message, reason: reason}, prefix) do
    _ = Logger.debug prefix <> message <> " (#{inspect reason})"
  end
end
