if Code.ensure_loaded?(:hackney) do
  defmodule Tesla.Adapter.Hackney do
    @moduledoc """
    Adapter for [hackney](https://github.com/benoitc/hackney).

    Remember to add `{:hackney, "~> 1.13"}` to dependencies (and `:hackney` to applications in `mix.exs`)
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

    - `:max_body` - Max response body size in bytes. Actual response may be bigger because hackney stops after the last chunk that surpasses `:max_body`.
    """
    @hackney_version Application.spec(:hackney, :vsn)
                     |> to_string()
                     |> Version.parse!()
    @behaviour Tesla.Adapter
    alias Tesla.Multipart

    # hackney 1.x uses references while hackney 2.x uses pids
    # https://github.com/benoitc/hackney/blob/master/guides/MIGRATION.md#connection-handle
    # further usage in code is the same
    defguard is_hackney_connection_handle(handle) when is_reference(handle) or is_pid(handle)

    @impl Tesla.Adapter
    def call(env, opts) do
      opts = process_options(opts)

      with {:ok, status, headers, body} <- request(env, opts) do
        {:ok, %{env | status: status, headers: format_headers(headers), body: format_body(body)}}
      end
    end

    # Hackney 3.X sets cacerts from certifi by default, which causes cacertfile to be ignored
    # Convert cacertfile to cacerts to fix SSL with custom CA certificates
    if Version.match?(@hackney_version, "~> 3.0") do
      defp process_options(opts) do
        process_ssl_options(opts)
      end

      defp process_ssl_options(opts) do
        case Keyword.get(opts, :ssl_options) do
          nil ->
            opts

          ssl_opts ->
            case Keyword.get(ssl_opts, :cacertfile) do
              nil ->
                opts

              cacertfile ->
                # Read and parse CA cert file
                {:ok, pem_data} = File.read(cacertfile)
                pem_entries = :public_key.pem_decode(pem_data)
                cacerts = Enum.map(pem_entries, fn {_type, der, _} -> der end)

                # Replace cacertfile with cacerts
                ssl_opts =
                  ssl_opts
                  |> Keyword.delete(:cacertfile)
                  |> Keyword.put(:cacerts, cacerts)

                Keyword.put(opts, :ssl_options, ssl_opts)
            end
        end
      end
    else
      defp process_options(opts), do: opts
    end

    defp format_headers(headers) do
      for {key, value} <- headers do
        {String.downcase(to_string(key)), to_string(value)}
      end
    end

    defp format_body(data) when is_list(data), do: IO.iodata_to_binary(data)
    defp format_body(data) when is_binary(data) or is_hackney_connection_handle(data), do: data

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
        case send_stream(ref, body) do
          :ok ->
            :hackney.finish_send_body(ref)
            handle(:hackney.start_response(ref), opts)

          error ->
            handle(error, opts)
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

    defp handle({:ok, handle}, _opts) when is_hackney_connection_handle(handle) do
      handle_async_response({handle, %{status: nil, headers: nil}})
    end

    if Version.match?(@hackney_version, "~> 1.0") do
      # Hackney 1.x: uses :hackney.body/2 with max_body parameter
      defp handle({:ok, status, headers, handle}, opts)
           when is_hackney_connection_handle(handle) do
        with {:ok, body} <- :hackney.body(handle, Keyword.get(opts, :max_body, :infinity)) do
          {:ok, status, headers, body}
        end
      end
    end

    if Version.match?(@hackney_version, "~> 3.0") do
      # Hackney 3.x: for streaming requests, :hackney.start_response returns handle as PID
      # Must use :hackney_conn.body/2 to read body with timeout
      defp handle({:ok, status, headers, handle}, opts)
           when is_hackney_connection_handle(handle) do
        timeout = Keyword.get(opts, :recv_timeout, :infinity)

        with {:ok, body} <- :hackney_conn.body(handle, timeout) do
          {:ok, status, headers, body}
        end
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
