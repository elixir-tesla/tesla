if Code.ensure_loaded?(:ibrowse) do
  defmodule Tesla.Adapter.Ibrowse do
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
        opts
      )
    end

    defp request(url, headers, method, %Stream{} = body, opts) do
      reductor = fn(item, _acc) -> {:suspend, item} end
      {_, _, fun} = Enumerable.reduce(body, {:suspend, nil}, reductor)
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

    defp next_chunk(fun), do: parse_chunk fun.({:cont, nil})

    defp parse_chunk({:suspended, item, fun}), do: {:ok, item, fun}
    defp parse_chunk(_),                       do: :eof

    defp handle({:error, {:conn_failed, error}}), do: error
    defp handle(response), do: response
  end
end
