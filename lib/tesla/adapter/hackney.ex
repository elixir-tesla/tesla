defmodule Tesla.Adapter.Hackney do
  def call(env) do
    with  {:ok, status, headers, ref} <- request(env),
          {:ok, body} <- :hackney.body(ref) do
      format_response(env, status, headers, body)
    end
  end

  defp format_response(env, status, headers, body) do
    headers = Enum.into(headers, %{})

    %{env | status:   status,
            headers:  headers,
            body:     body}
  end

  defp request(env) do
    request(env.method, to_char_list(env.url), Enum.into(env.headers, []), env.body)
  end
  defp request(method, url, headers, %Stream{} = body), do: request_stream(method, url, headers, body)
  defp request(method, url, headers, body) when is_function(body), do: request_stream(method, url, headers, body)
  defp request(method, url, headers, body) do
    :hackney.request(method, url, headers, body || '')
  end


  defp request_stream(method, url, headers, body) do
    {:ok, ref} = :hackney.request(method, url, headers, :stream)
    for data <- body, do: :ok = :hackney.send_body(ref, data)
    :hackney.start_response(ref)
  end
end
