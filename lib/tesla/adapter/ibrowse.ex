defmodule Tesla.Adapter.Ibrowse do
  def call(env) do
    if target = env.opts[:respond_to] do
       
      gatherer = spawn_link fn -> gather_response(env, target, nil, nil, nil) end

      opts = List.keyreplace(env.opts, :respond_to, 0, stream_to: gatherer)
      {:ibrowse_req_id, id} = send_req(env, opts)
      {:ok, id}
    else
      {:ok, status, headers, body} = send_req(env, env.opts)
      format_response(env, status, headers, body)
    end
  end

  defp format_response(env, status, headers, body) do
    {status, _} = Integer.parse(to_string(status))
    headers     = Enum.into(headers, %{})

    %{env | status:   status,
            headers:  headers,
            body:     body}
  end

  defp send_req(env, opts) do
    body = env.body || []
    :ibrowse.send_req(
      env.url |> to_char_list,
      Enum.into(env.headers, []),
      env.method,
      body,
      opts
    )
  end

  defp gather_response(env, target, status, headers, body) do
    receive do
      {:ibrowse_async_headers, _, new_status, new_headers} ->
        gather_response(env, target, new_status, new_headers, body)

      {:ibrowse_async_response, _, append_body} ->
        new_body = if body, do: body <> append_body, else: append_body
        gather_response(env, target, status, headers, new_body)

      {:ibrowse_async_response_end, _} ->
        response = format_response(env, status, headers, body)
        send target, {:tesla_response, response}
    end
  end
end
