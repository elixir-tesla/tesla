defmodule Tesla.Adapter.Httpc do
  @http_opts ~w(timeout connect_timeout ssl essl autoredirect proxy_auth version relaxed url_encode)a

  def call(env, opts) do
    with {:ok, {status, headers, body}} <- request(env, opts || []) do
      format_response(env, status, headers, body)
    end
  end

  defp format_response(env, {_, status, _}, headers, body) do
    %{env | status:   status,
            headers:  headers,
            body:     body}
  end

  defp request(env, opts) do
    content_type = to_char_list(env.headers["content-type"] || "")
    handle request(
      env.method || :get,
      Tesla.build_url(env.url, env.query) |> to_char_list,
      Enum.into(env.headers, [], fn {k,v} -> {to_char_list(k), to_char_list(v)} end),
      content_type,
      env.body,
      Keyword.split(opts ++ env.opts, @http_opts)
    )
  end

  defp request(method, url, headers, _content_type, nil, {http_opts, opts}) do
    :httpc.request(method, {url, headers}, http_opts, opts)
  end

  defp request(method, url, headers, content_type, body, {http_opts, opts}) do
    :httpc.request(method, {url, headers, content_type, body}, http_opts, opts)
  end

  defp handle({:error, {:failed_connect, _}}), do: {:error, :econnrefused}
  defp handle(response), do: response
end
