if Code.ensure_loaded?(:gun) do
  defmodule Tesla.Adapter.Gun do
    @moduledoc """
    Adapter for [gun] https://github.com/ninenines/gun

    Remember to add `{:gun, "~> 1.3"}` to dependencies
    Also, you need to recompile tesla after adding `:gun` dependency:
    ```
    mix deps.clean tesla
    mix deps.compile tesla
    ```
    ### Example usage
    ```
    # set globally in config/config.exs
    config :tesla, :adapter, Pleroma.Tesla.Adapter.Gun
    # set per module
    defmodule MyClient do
      use Tesla
      adapter Pleroma.Tesla.Adapter.Gun
    end
    ```

    ### Options:

    * `connect_timeout` - Connection timeout.
    * `http_opts` - Options specific to the HTTP protocol.
    * `http2_opts` -  Options specific to the HTTP/2 protocol.
    * `protocols` - Ordered list of preferred protocols. Defaults: [http2, http] - for :tls, [http] - for :tcp.
    * `retry` - Number of times Gun will try to reconnect on failure before giving up. Default: 5
    * `retry_timeout` - Time between retries in milliseconds. Default: 5000
    * `trace` - Whether to enable dbg tracing of the connection process. Should only be used during debugging. Default: false.
    * `transport` - Whether to use TLS or plain TCP. The default varies depending on the port used. Port 443 defaults to tls.
                    All other ports default to tcp.
    * `transport_opts` - Transport options. They are TCP options or TLS options depending on the selected transport. Default: [].
    * `ws_opts` - Options specific to the Websocket protocol. Default: %{}.
        * `compress` - Whether to enable permessage-deflate compression. This does not guarantee that compression will
                        be used as it is the server that ultimately decides. Defaults to false.
        * `protocols` - A non-empty list enables Websocket protocol negotiation. The list of protocols will be sent
                        in the sec-websocket-protocol request header.
                        The handler module interface is currently undocumented and must be set to `gun_ws_h`.
    }

    """
    @behaviour Tesla.Adapter
    alias Tesla.Multipart

    @default [
      connect_timeout: 1000,
      retry: 3,
      retry_timeout: 1000,
      max_body: 2_000_000,
      timeout: 2_000
    ]

    @gun_keys [
      :connect_timeout,
      :http_opts,
      :http2_opts,
      :protocols,
      :retry,
      :retry_timeout,
      :trace,
      :transport,
      :transport_opts,
      :ws_opts
    ]

    @impl true
    @doc false
    def call(env, opts) do
      with {:ok, status, headers, body} <- request(env, opts) do
        {:ok, %{env | status: status, headers: format_headers(headers), body: body}}
      end
    end

    defp format_headers(headers) do
      for {key, value} <- headers do
        {String.downcase(to_string(key)), to_string(value)}
      end
    end

    defp format_method(method), do: String.upcase(to_string(method))

    defp format_url(nil, nil), do: ""
    defp format_url(nil, query), do: "?" <> query
    defp format_url(path, nil), do: path
    defp format_url(path, query), do: path <> "?" <> query

    defp request(env, opts) do
      request(
        format_method(env.method),
        Tesla.build_url(env.url, env.query),
        env.headers,
        env.body || "",
        Tesla.Adapter.opts(@default, env, opts) |> Enum.into(%{})
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
      with {pid, f_url} <- open_conn(url, opts),
           stream <- open_stream(pid, method, f_url, headers, body, false) do
        read_response(pid, stream, opts)
      end
    end

    defp request_stream(method, url, headers, body, opts) do
      with {pid, f_url} <- open_conn(url, opts),
           stream <- open_stream(pid, method, f_url, headers, body, true) do
        read_response(pid, stream, opts)
      end
    end

    defp open_conn(url, opts) do
      uri = URI.parse(url)
      opts = if uri.scheme == "https", do: Map.put(opts, :transport, :tls), else: opts
      {:ok, pid} = :gun.open(to_charlist(uri.host), uri.port, Map.take(opts, @gun_keys))
      {pid, format_url(uri.path, uri.query)}
    end

    defp open_stream(pid, method, url, headers, body, true) do
      stream = :gun.request(pid, method, url, headers, "")
      for data <- body, do: :ok = :gun.data(pid, stream, :nofin, data)
      :gun.data(pid, stream, :fin, "")
      stream
    end

    defp open_stream(pid, method, url, headers, body, false),
      do: :gun.request(pid, method, url, headers, body)

    defp read_response(pid, stream, opts) do
      receive do
        msg ->
          case msg do
            {:gun_response, ^pid, ^stream, :fin, status, headers} ->
              {:ok, status, headers, ""}

            {:gun_response, ^pid, ^stream, :nofin, status, headers} ->
              mref = Process.monitor(pid)

              case read_body(pid, stream, mref, opts) do
                {:error, error} ->
                  {:error, error}

                body ->
                  {:ok, status, headers, body}
              end

            {:error, error} ->
              {:error, error}

            {:gun_up, ^pid, :http} ->
              read_response(pid, stream, opts)

            msg ->
              IO.inspect(msg)
              IO.inspect("unsupported message received in read response.")
              msg
          end
      after
        opts[:timeout] ->
          {:error, "read response timeout"}
      end
    end

    defp read_body(pid, stream, mref, opts, acc \\ "") do
      limit = opts[:max_body]

      receive do
        msg ->
          case msg do
            {:gun_data, ^pid, ^stream, :fin, body} ->
              if limit - byte_size(body) >= 0 do
                acc <> body
              else
                {:error, "body too large"}
              end

            {:gun_data, ^pid, ^stream, :nofin, part} ->
              if limit - byte_size(part) >= 0 do
                read_body(pid, stream, mref, opts, acc <> part)
              else
                {:error, "body too large"}
              end

            msg ->
              IO.inspect(msg)
              IO.inspect("unsupported message received in read body.")
              msg
          end
      after
        opts[:timeout] ->
          {:error, "read body timeout"}
      end
    end
  end
end
