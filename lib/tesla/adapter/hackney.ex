defmodule Tesla.Adapter.Hackney do
  def call(env) do
    {:ok, status, headers, ref} = request(env)
    {:ok, body} = :hackney.body(ref)

    format_response(env, status, headers, body)
  end

  defp format_response(env, status, headers, body) do
    headers = Enum.into(headers, %{})

    %{env | status:   status,
            headers:  headers,
            body:     body}
  end

  defp request(env) do
    :hackney.request(env.method, to_char_list(env.url), Enum.into(env.headers, []), env.body || '')
  end
end
