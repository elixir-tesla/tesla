defmodule Tesla.Adapter.Httpc do
  @moduledoc """
  Adapter for [httpc](http://erlang.org/doc/man/httpc.html)

  This is the default adapter.

  **NOTE** Tesla overrides default autoredirect value with false to ensure
  consistency between adapters
  """

  import Tesla.Adapter.Shared, only: [stream_to_fun: 1, next_chunk: 1]
  alias Tesla.Multipart

  @override_defaults autoredirect: false
  @http_opts ~w(timeout connect_timeout ssl essl autoredirect proxy_auth version relaxed url_encode)a

  def call(env, opts) do
    env = Tesla.Adapter.Shared.capture_query_params(env)
    opts = Keyword.merge(@override_defaults, opts || [])

    with {:ok, {status, headers, body}} <- request(env, opts) do
      format_response(env, status, headers, body)
    end
  end

  defp format_response(env, {_, status, _}, headers, body) do
    %{env | status:   status,
            headers:  headers,
            body:     body}
  end

  defp request(env, opts) do
    content_type = to_charlist(env.headers["content-type"] || "")
    handle request(
      env.method || :get,
      Tesla.build_url(env.url, env.query) |> to_charlist,
      Enum.into(env.headers, [], fn {k,v} -> {to_charlist(k), to_charlist(v)} end),
      content_type,
      env.body,
      Keyword.split(opts ++ env.opts, @http_opts)
    )
  end

  defp request(method, url, headers, _content_type, nil, {http_opts, opts}) do
    :httpc.request(method, {url, headers}, http_opts, opts)
  end

  defp request(method, url, headers, _content_type, %Multipart{} = mp, opts) do
    headers = headers ++ Multipart.headers(mp)
    headers = for {key, value} <- headers, do: {to_charlist(key), to_charlist(value)}
    {content_type, headers} = Keyword.pop_first(headers, 'Content-Type', 'text/plain')
    body = stream_to_fun(Multipart.body(mp))

    request(method, url, headers, to_charlist(content_type), body, opts)
  end

  defp request(method, url, headers, content_type, %Stream{} = body, opts) do
    fun = stream_to_fun(body)
    request(method, url, headers, content_type, fun, opts)
  end

  defp request(method, url, headers, content_type, body, opts) when is_function(body) do
    body = {:chunkify, &next_chunk/1, body}
    request(method, url, headers, content_type, body, opts)
  end

  defp request(method, url, headers, content_type, body, {http_opts, opts}) do
    :httpc.request(method, {url, headers, content_type, body}, http_opts, opts)
  end

  defp handle({:error, {:failed_connect, _}}), do: {:error, :econnrefused}
  defp handle(response), do: response
end
