defmodule Tesla.Adapter.Httpc do
  def call(env) do
    with {:ok, {status, headers, body}} <- request(env) do
      format_response(env, status, headers, body)
    end
  end

  defp format_response(env, {_, status, _}, headers, body) do
    headers     = Enum.into(headers, %{})

    %{env | status:   status,
            headers:  headers,
            body:     body}
  end

  defp request(env) do
    content_type = env.headers['Content-Type'] || ''
    request(
      env.method,
      to_char_list(env.url),
      Enum.into(env.headers, []),
      content_type,
      env.body
    )
  end

  defp request(method, url, headers, _content_type, nil) do
    :httpc.request(method, {url, headers}, [], [])
  end

  defp request(method, url, headers, content_type, body) do
    :httpc.request(method, {url, headers, content_type, body}, [], [])
  end
end
