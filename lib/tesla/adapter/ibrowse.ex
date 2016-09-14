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
      handle :ibrowse.send_req(
        Tesla.build_url(env.url, env.query) |> to_char_list,
        Enum.into(env.headers, []),
        env.method,
        body,
        opts
      )
    end

    defp handle({:error, {:conn_failed, error}}), do: error
    defp handle(response), do: response
  end
end
