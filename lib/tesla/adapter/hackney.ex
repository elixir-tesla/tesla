if Code.ensure_loaded?(:hackney) do
  defmodule Tesla.Adapter.Hackney do
    def call(env, opts) do
      with  {:ok, status, headers, body} <- request(env, opts || []) do
        %{env | status:   status,
                headers:  headers,
                body:     body}
      end
    end

    defp request(env, opts) do
      request(
        env.method,
        Tesla.build_url(env.url, env.query),
        Enum.into(env.headers, []),
        env.body,
        opts ++ env.opts
      )
    end
    defp request(method, url, headers, %Stream{} = body, opts), do: request_stream(method, url, headers, body, opts)
    defp request(method, url, headers, body, opts) when is_function(body), do: request_stream(method, url, headers, body, opts)
    defp request(method, url, headers, body, opts) do
      handle :hackney.request(method, url, headers, body || '', opts)
    end


    defp request_stream(method, url, headers, body, opts) do
      with {:ok, ref} <- :hackney.request(method, url, headers, :stream, opts) do
        for data <- body, do: :ok = :hackney.send_body(ref, data)
        handle :hackney.start_response(ref)
      else
        e -> handle(e)
      end
    end

    defp handle({:error, _} = error), do: error
    defp handle({:ok, status, headers}), do: {:ok, status, headers, []}
    defp handle({:ok, status, headers, ref}) do
      with {:ok, body} <- :hackney.body(ref) do
        {:ok, status, headers, body}
      end
    end
  end
end
