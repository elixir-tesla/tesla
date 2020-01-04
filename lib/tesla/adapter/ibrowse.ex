if Code.ensure_loaded?(:ibrowse) do
  defmodule Tesla.Adapter.Ibrowse do
    @moduledoc """
    Adapter for [ibrowse](https://github.com/cmullaparthi/ibrowse).

    Remember to add `{:ibrowse, "~> 4.2"}` to dependencies (and `:ibrowse` to applications in `mix.exs`)
    Also, you need to recompile tesla after adding `:ibrowse` dependency:

    ```
    mix deps.clean tesla
    mix deps.compile tesla
    ```

    ## Example usage

    ```
    # set globally in config/config.exs
    config :tesla, :adapter, Tesla.Adapter.Ibrowse

    # set per module
    defmodule MyClient do
      use Tesla

      adapter Tesla.Adapter.Ibrowse
    end
    ```
    """

    @behaviour Tesla.Adapter
    import Tesla.Adapter.Shared, only: [stream_to_fun: 1, next_chunk: 1]
    alias Tesla.Multipart

    @impl Tesla.Adapter
    def call(env, opts) do
      with {:ok, status, headers, body} <- request(env, opts) do
        {:ok,
         %{
           env
           | status: format_status(status),
             headers: format_headers(headers),
             body: format_body(body)
         }}
      end
    end

    defp format_status(status) when is_list(status) do
      status |> to_string() |> String.to_integer()
    end

    defp format_headers(headers) do
      for {key, value} <- headers do
        {String.downcase(to_string(key)), to_string(value)}
      end
    end

    defp format_body(data) when is_list(data), do: IO.iodata_to_binary(data)
    defp format_body(data) when is_binary(data), do: data

    defp request(env, opts) do
      body = env.body || []

      handle(
        request(
          Tesla.build_url(env.url, env.query) |> to_charlist,
          env.headers,
          env.method,
          body,
          Tesla.Adapter.opts(env, opts)
        )
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
      {timeout, opts} = opts |> Keyword.pop(:timeout, 30_000)
      :ibrowse.send_req(url, headers, method, body, opts, timeout)
    end

    defp handle({:error, {:conn_failed, error}}), do: error
    defp handle(response), do: response
  end
end
