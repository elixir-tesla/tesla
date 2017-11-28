if Code.ensure_loaded?(:hackney) do
  defmodule Tesla.Adapter.Hackney do
    @moduledoc """
    Adapter for [hackney](https://github.com/benoitc/hackney)

    Remember to add `{:hackney, "~> 1.6"}` to dependencies (and `:hackney` to applications in `mix.exs`)
    Also, you need to recompile tesla after adding `:hackney` dependency:

    ```
    mix deps.clean tesla
    mix deps.compile tesla
    ```

    ### Example usage
    ```
    # set globally in config/config.exs
    config :tesla, :adapter, :hackney

    # set per module
    defmodule MyClient do
      use Tesla

      adapter :hackney
    end
    ```
    """

    alias Tesla.Multipart

    def call(env, opts) do
      env = Tesla.Adapter.Shared.capture_query_params(env)

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
    defp request(method, url, headers, %Multipart{} = mp, opts) do
      headers = headers ++ Multipart.headers(mp)
      body = Multipart.body(mp)

      request(method, url, headers, body, opts)
    end
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
    defp handle({:ok, status, headers, ref}) when is_reference(ref) do
      with {:ok, body} <- :hackney.body(ref) do
        {:ok, status, headers, body}
      end
    end
    defp handle({:ok, status, headers, body}), do: {:ok, status, headers, body}
  end
end
