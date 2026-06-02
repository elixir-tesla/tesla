if Code.ensure_loaded?(:hackney) do
  defmodule Tesla.Adapter.Hackney do
    @moduledoc """
    Adapter for [hackney](https://github.com/benoitc/hackney).

    Remember to add `{:hackney, "~> 4.0"}` to dependencies (and `:hackney` to applications in `mix.exs`)
    Also, you need to recompile tesla after adding `:hackney` dependency:

    ```shell
    mix deps.clean tesla
    mix deps.compile tesla
    ```

    ## Examples

    ```elixir
    # set globally in config/config.exs
    config :tesla, :adapter, Tesla.Adapter.Hackney

    # set per module
    defmodule MyClient do
      def client do
        Tesla.client([], Tesla.Adapter.Hackney)
      end
    end
    ```

    ## Adapter specific options

    - `:max_body` - Max response body size in bytes. Only applied when the
      response is streamed (`async: true` or streaming request body). For sync
      requests hackney always reads the full body inline and this option has
      no effect. Actual response may be bigger because hackney stops after the
      last chunk that surpasses `:max_body`.
    """
    @behaviour Tesla.Adapter
    alias Tesla.Multipart

    # Hackney 4.1.0's `request_ret/0` typespec lists `{:ok, reference()}` for the async
    # and stream-upload returns, but the implementation actually returns `{:ok, pid()}`.
    # Until the upstream fix is released, dialyzer cannot prove the `is_pid` guards in
    # `handle/2` succeed and flags the streaming code paths as unreachable.
    # Upstream fix: https://github.com/benoitc/hackney (request_ret + request_async specs)
    @dialyzer {:nowarn_function,
               [
                 request: 5,
                 request_stream: 5,
                 send_stream: 2,
                 handle: 2,
                 handle_async_response: 1,
                 read_response_body: 2,
                 read_response_body: 4,
                 format_body: 1
               ]}

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
    defp format_body(data) when is_binary(data), do: data
    defp format_body(data) when is_pid(data), do: data

    defp request(env, opts) do
      request(
        env.method,
        Tesla.build_url(env),
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
      handle(:hackney.request(method, url, headers, body || ~c"", opts), opts)
    end

    defp request_stream(method, url, headers, body, opts) do
      with {:ok, ref} <- :hackney.request(method, url, headers, :stream, opts) do
        with :ok <- send_stream(ref, body),
             :ok <- :hackney.finish_send_body(ref) do
          handle(:hackney.start_response(ref), opts)
        else
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

    defp handle({:connect_error, {:error, reason}}, _opts), do: {:error, reason}
    defp handle({:error, _} = error, _opts), do: error
    defp handle({:ok, status, headers}, _opts), do: {:ok, status, headers, []}

    defp handle({:ok, ref}, _opts) when is_pid(ref) do
      handle_async_response({ref, %{status: nil, headers: nil}})
    end

    defp handle({:ok, status, headers, ref}, opts) when is_pid(ref) do
      with {:ok, body} <- read_response_body(ref, Keyword.get(opts, :max_body, :infinity)) do
        {:ok, status, headers, body}
      end
    end

    defp handle({:ok, status, headers, body}, _opts), do: {:ok, status, headers, body}

    defp read_response_body(ref, :infinity), do: :hackney.body(ref)

    defp read_response_body(ref, max) when is_integer(max) do
      read_response_body(ref, max, [], 0)
    end

    defp read_response_body(ref, max, acc, size) do
      case :hackney.stream_body(ref) do
        :done ->
          {:ok, IO.iodata_to_binary(Enum.reverse(acc))}

        {:ok, chunk} when size + byte_size(chunk) >= max ->
          :hackney.close(ref)
          {:ok, IO.iodata_to_binary(Enum.reverse([chunk | acc]))}

        {:ok, chunk} ->
          read_response_body(ref, max, [chunk | acc], size + byte_size(chunk))

        {:error, _} = error ->
          error
      end
    end

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
