defmodule Tesla.Adapter.Httpc do
  def call(env, _opts) do
    with {:ok, {status, headers, body}} <- request(env) do
      format_response(env, status, headers, body)
    end
  end

  defp format_response(env, {_, status, _}, headers, body) do
    %{env | status:   status,
            headers:  headers,
            body:     body}
  end

  defp request(env) do
    content_type = to_char_list(env.headers["content-type"] || "")
    handle request(
      env.method || :get,
      Tesla.build_url(env.url, env.query) |> to_char_list,
      Enum.into(env.headers, [], fn {k,v} -> {to_char_list(k), to_char_list(v)} end),
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

  defp handle({:error, {:failed_connect, _}}), do: {:error, :econnrefused}
  defp handle(response), do: response
end
