if Code.ensure_loaded?(:katipo) do
  defmodule Tesla.Adapter.Katipo do
    @pool :tesla

    def call(env, opts) do
      ensure_pool_exists(env.opts ++ opts)
      with  {:ok, %{status: status, headers: headers, body: body}} <- request(env, opts || []) do
        %{env | status:   status,
                headers:  headers,
                body:     body}
      end
    end

    defp ensure_pool_exists(opts) do
      :katipo_pool.start(@pool, 50, opts || [])
    catch
      :error, :exists -> :ok
    end

    defp request(env, opts) do
      request(
        env.method || :get,
        Tesla.build_url(env.url, env.query),
        Enum.into(env.headers, []),
        env.body,
        Enum.into(opts ++ env.opts, %{})
      )
    end

    defp request(method, url, headers, nil, opts) do
      handle :katipo.req(
        @pool,
        Map.merge(%{method: method, url: url, headers: headers}, opts)
      )
    end

    defp request(method, url, headers, body, opts) do
      handle :katipo.req(
        @pool,
        Map.merge(%{method: method, url: url, headers: headers, body: body}, opts)
      )
    end

    defp handle({:error, %{code: :couldnt_connect}}), do: {:error, :econnrefused}
    defp handle(response), do: response
  end
end
