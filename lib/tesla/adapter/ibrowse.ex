if Code.ensure_loaded?(:ibrowse) do
  defmodule Tesla.Adapter.Ibrowse do
    @moduledoc """
    Adapter for [ibrowse](https://github.com/cmullaparthi/ibrowse)

    Remember to add `{:ibrowse, "~> 4.2"}` to dependencies (and `:ibrowse` to applications in `mix.exs`)
    Also, you need to recompile tesla after adding `:ibrowse` dependency:

    ```
    mix deps.clean tesla
    mix deps.compile tesla
    ```

    ### Example usage
    ```
    # set globally in config/config.exs
    config :tesla, :adapter, :ibrowse

    # set per module
    defmodule MyClient do
      use Tesla

      adapter :ibrowse
    end
    ```
    """

    import Tesla.Adapter.Shared, only: [stream_to_fun: 1, next_chunk: 1]
    alias Tesla.Multipart

    def call(env, opts) do
      env = Tesla.Adapter.Shared.capture_query_params(env)

      with {:ok, status, headers, body} <- request(env, opts || []) do
        %{env | status:   status,
                headers:  headers,
                body:     body}
      end
    end

    defp request(env, opts) do
      body = env.body || []
      handle request(
        Tesla.build_url(env.url, env.query) |> to_charlist,
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
