if Code.ensure_loaded?(:ibrowse) do
  defmodule Tesla.Adapter.Ibrowse do
    import Tesla.Adapter.Shared, only: [stream_to_fun: 1, next_chunk: 1]
    alias Tesla.Multipart

    def call(env, opts) do
      with {:ok, status, headers, body} <- request(env, opts || []) do
        %{env | status:   status,
                headers:  headers,
                body:     body}
      end
    end

    defp request(env, opts) do
      body = env.body || []
      handle request(
        Tesla.build_url(env.url, env.query) |> to_char_list,
        Enum.into(env.headers, []),
        env.method,
        body,
        opts ++ env.opts
      )
    end

    defp request(url, headers, method, %Multipart{} = mp, opts) do
      headers = headers ++ Multipart.headers(mp)
      body = stream_to_fun(Multipart.body(mp))

      request(url, headers, method, body, opts)
    end

    defp request(url, headers, method, %Stream{} = body, opts) do
      fun = stream_to_fun(body)
      request(url, headers, method, fun, opts)
    end

    defp request(url, headers, method, body, opts) when is_function(body) do
      body = {&next_chunk/1, body}
      opts = Keyword.put(opts, :transfer_encoding, :chunked)
      request(url, headers, method, body, opts)
    end

    defp request(url, headers, method, body, opts) do
      :ibrowse.send_req(url, headers, method, body, opts)
    end

    defp handle({:error, {:conn_failed, error}}), do: error
    defp handle(response), do: response
  end
end
