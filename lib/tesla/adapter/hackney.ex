if Code.ensure_loaded?(:hackney) do
  defmodule Tesla.Adapter.Hackney do
    @moduledoc """
    Adapter for [hackney](https://github.com/benoitc/hackney).

    Remember to add `{:hackney, "~> 1.13"}` to dependencies (and `:hackney` to applications in `mix.exs`)
    Also, you need to recompile tesla after adding `:hackney` dependency:

    ```
    mix deps.clean tesla
    mix deps.compile tesla
    ```

    ## Examples

    ```
    # set globally in config/config.exs
    config :tesla, :adapter, Tesla.Adapter.Hackney

    # set per module
    defmodule MyClient do
      use Tesla

      adapter Tesla.Adapter.Hackney
    end
    ```

    ## Adapter specific options

    - `:max_body` - Max response body size in bytes. Actual response may be bigger because hackney stops after the last chunk that surpasses `:max_body`.
    """
    @behaviour Tesla.Adapter
    alias Tesla.Multipart

    @impl Tesla.Adapter
    def call(env, opts) do
      with {:ok, status, headers, body} <- request(env, opts) do
        {:ok, %{env | status: status, headers: format_headers(headers), body: format_body(body)}}
      end
    end

    defp format_headers(headers) do
      for {key, value} <- headers do
        {String.downcase(to_string(key)), to_string(value)}
      end
    end

    defp format_body(data) when is_list(data), do: IO.iodata_to_binary(data)
    defp format_body(data) when is_binary(data) or is_reference(data), do: data

    defp request(env, opts) do
      request(
        env.method,
        Tesla.build_url(env.url, env.query),
        env.headers,
        env.body,
        Tesla.Adapter.opts(env, opts)
      )
    end

    defp request(method, url, headers, %Stream{} = body, opts),
      do: request_stream(method, url, headers, body, opts)

    defp request(method, url, headers, body, opts) when is_function(body),
      do: request_stream(method, url, headers, body, opts)

    defp request(method, url, headers, %Multipart{} = mp, opts) do
      headers = headers ++ Multipart.headers(mp)
      body = Multipart.body(mp)

      request(method, url, headers, body, opts)
    end

    defp request(method, url, headers, body, opts) do
      handle(:hackney.request(method, url, headers, body || '', opts), opts)
    end

    defp request_stream(method, url, headers, body, opts) do
      with {:ok, ref} <- :hackney.request(method, url, headers, :stream, opts) do
        case send_stream(ref, body) do
          :ok -> handle(:hackney.start_response(ref), opts)
          error -> handle(error, opts)
        end
      else
        e -> handle(e, opts)
      end
    end

    defp send_stream(ref, body) do
      Enum.reduce_while(body, :ok, fn data, _ ->
        case :hackney.send_body(ref, data) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end

    defp handle({:error, _} = error, _opts), do: error
    defp handle({:ok, status, headers}, _opts), do: {:ok, status, headers, []}

    defp handle({:ok, ref}, _opts) when is_reference(ref) do
      handle_async_response({ref, %{status: nil, headers: nil}})
    end

    defp handle({:ok, status, headers, ref}, opts) when is_reference(ref) do
      with {:ok, body} <- :hackney.body(ref, Keyword.get(opts, :max_body, :infinity)) do
        {:ok, status, headers, body}
      end
    end

    defp handle({:ok, status, headers, body}, _opts), do: {:ok, status, headers, body}

    defp handle_async_response({ref, %{headers: headers, status: status}})
         when not (is_nil(headers) or is_nil(status)) do
      {:ok, status, headers, ref}
    end

    defp handle_async_response({ref, output}) do
      receive do
        {:hackney_response, ^ref, {:status, status, _}} ->
          handle_async_response({ref, %{output | status: status}})

        {:hackney_response, ^ref, {:headers, headers}} ->
          handle_async_response({ref, %{output | headers: headers}})
      end
    end
  end
end
