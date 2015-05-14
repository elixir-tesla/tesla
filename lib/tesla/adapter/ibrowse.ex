defmodule Tesla.Adapter.Ibrowse do
  def start do
    :ibrowse.start
  end

  def call(env) do
    opts = []

    if target = env.opts[:respond_to] do

      gatherer = spawn_link fn -> gather_response(env, target, {:ok, nil, nil, nil}) end

      opts = opts ++ [stream_to: gatherer]
      {:ibrowse_req_id, id} = send_req(env, opts)
      {:ok, id}
    else
      format_response(env, send_req(env, opts))
    end
  end

  defp format_response(env, res) do
    {:ok, status, headers, body} = res

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

  defp gather_response(env, target, res) do
    {:ok, _status, _headers, _body} = res

    receive do
      {:ibrowse_async_headers, _, status, headers} ->
        gather_response(env, target, {:ok, status, headers, _body})

      {:ibrowse_async_response, _, body} ->
        body = if _body do
          _body <> body
        else
          body
        end

        gather_response(env, target, {:ok, _status, _headers, body})

      {:ibrowse_async_response_end, _} ->
        response = format_response(env, res)
        send target, {:tesla_response, response}
    end
  end
end
