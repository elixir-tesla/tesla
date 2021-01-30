if Code.ensure_loaded?(:gun) do
  defmodule Tesla.Adapter.Gun do
    @moduledoc """
    Adapter for [gun](https://github.com/ninenines/gun).

    Remember to add `{:gun, "~> 1.3"}`, `{:idna, "~> 6.0"}` and `{:castore, "~> 0.1"}` to dependencies.

    In version 1.3 gun sends `host` header with port. Fixed in master branch.
    Also, you need to recompile tesla after adding `:gun` dependency:

    ```
    mix deps.clean tesla
    mix deps.compile tesla
    ```

    ## Examples

    ```
    # set globally in config/config.exs
    config :tesla, :adapter, Tesla.Adapter.Gun

    # set per module
    defmodule MyClient do
      use Tesla
      adapter Tesla.Adapter.Gun
    end
    ```

    ## Adapter specific options

    - `:timeout` - Time, while process, will wait for gun messages.

    - `:body_as` - What will be returned in `%Tesla.Env{}` body key. Possible values:
        - `:plain` - as binary (default).
        - `:stream` - as stream.
            If you don't want to close connection (because you want to reuse it later)
            pass `close_conn: false` in adapter opts.
        - `:chunks` - as chunks.
            You can get response body in chunks using `Tesla.Adapter.Gun.read_chunk/3` function.

        Processing of the chunks and checking body size must be done by yourself.
        Example of processing function is in `test/tesla/adapter/gun_test.exs` - `Tesla.Adapter.GunTest.read_body/4`.
        If you don't need connection later don't forget to close it with `Tesla.Adapter.Gun.close/1`.

    - `:max_body` - Max response body size in bytes.
        Works only with `body_as: :plain`, with other settings you need to check response body size by yourself.

    - `:conn` - Opened connection pid with gun. Is used for reusing gun connections.

    - `:close_conn` - Close connection or not after receiving full response body.
        Is used for reusing gun connections. Defaults to `true`.

    - `:certificates_verification` - Add SSL certificates verification.
        [erlang-certifi](https://github.com/certifi/erlang-certifi)
        [ssl_verify_fun.erl](https://github.com/deadtrickster/ssl_verify_fun.erl)

    - `:proxy` - Proxy for requests.
        **Socks proxy are supported only for gun master branch**.
        Examples: `{'localhost', 1234}`, `{{127, 0, 0, 1}, 1234}`, `{:socks5, 'localhost', 1234}`.

      **NOTE:** By default GUN uses TLS as transport if the specified port is 443,
        if TLS is required for proxy connection on another port please specify transport
        using the Gun options below otherwise tcp will be used.

    - `:proxy_auth` - Auth to be passed along with the proxy opt.
        Supports Basic auth for regular and Socks proxy.
        Format: `{proxy_username, proxy_password}`.

    ## [Gun options](https://ninenines.eu/docs/en/gun/1.3/manual/gun/)

    - `:connect_timeout` - Connection timeout.

    - `:http_opts` - Options specific to the HTTP protocol.

    - `:http2_opts` -  Options specific to the HTTP/2 protocol.

    - `:protocols` - Ordered list of preferred protocols.
        Defaults: `[:http2, :http]`- for :tls, `[:http]` - for :tcp.

    - `:trace` - Whether to enable dbg tracing of the connection process.
        Should only be used during debugging. Default: false.

    - `:transport` - Whether to use TLS or plain TCP.
        The default varies depending on the port used.
        Port 443 defaults to tls. All other ports default to tcp.

    - `:transport_opts` - Transport options.
        They are TCP options or TLS options depending on the selected transport.
        Default: `[]`. Gun version: 1.3.

    - `:tls_opts` - TLS transport options.
        Default: `[]`. Gun from master branch.

    - `:tcp_opts` - TCP trasnport options.
        Default: `[]`. Gun from master branch.

    - `:socks_opts` - Options for socks.
        Default: `[]`. Gun from master branch.

    - `:ws_opts` - Options specific to the Websocket protocol. Default: `%{}`.

        - `:compress` - Whether to enable permessage-deflate compression.
            This does not guarantee that compression will be used as it is the server
            that ultimately decides. Defaults to false.

        - `:protocols` - A non-empty list enables Websocket protocol negotiation.
            The list of protocols will be sent in the sec-websocket-protocol request header.
            The handler module interface is currently undocumented and must be set to `gun_ws_h`.
    """
    @behaviour Tesla.Adapter
    alias Tesla.Multipart

    # TODO: update list after update to gun 2.0
    @gun_keys [
      :connect_timeout,
      :http_opts,
      :http2_opts,
      :protocols,
      :retry,
      :retry_timeout,
      :trace,
      :transport,
      :socks_opts,
      :ws_opts
    ]

    @default_timeout 1_000

    @impl Tesla.Adapter
    def call(env, opts) do
      with {:ok, status, headers, body} <- request(env, opts) do
        {:ok, %{env | status: status, headers: format_headers(headers), body: body}}
      end
    end

    @doc """
    Reads chunk of the response body.

    Returns `{:fin, binary()}` if all body received, otherwise returns `{:nofin, binary()}`.
    """
    @spec read_chunk(pid(), reference(), keyword() | map()) ::
            {:fin, binary()} | {:nofin, binary()} | {:error, atom()}
    def read_chunk(pid, stream, opts) do
      with {status, _} = chunk when status in [:fin, :error] <- do_read_chunk(pid, stream, opts) do
        if opts[:close_conn], do: close(pid)
        chunk
      end
    end

    defp do_read_chunk(pid, stream, opts) do
      receive do
        {:gun_data, ^pid, ^stream, :fin, body} ->
          {:fin, body}

        {:gun_data, ^pid, ^stream, :nofin, part} ->
          {:nofin, part}

        {:DOWN, _, _, _, reason} ->
          {:error, reason}
      after
        opts[:timeout] || @default_timeout ->
          {:error, :recv_chunk_timeout}
      end
    end

    @doc """
    Brutally close the `gun` connection.
    """
    @spec close(pid()) :: :ok
    defdelegate close(pid), to: :gun

    defp format_headers(headers) do
      for {key, value} <- headers do
        {String.downcase(to_string(key)), to_string(value)}
      end
    end

    defp request(env, opts) do
      request(
        Tesla.Adapter.Shared.format_method(env.method),
        Tesla.build_url(env.url, env.query),
        format_headers(env.headers),
        env.body || "",
        Tesla.Adapter.opts(
          [close_conn: true, body_as: :plain, send_body: :at_once, receive: true],
          env,
          opts
        )
        |> Enum.into(%{})
      )
    end

    defp request(method, url, headers, %Stream{} = body, opts),
      do: do_request(method, url, headers, body, Map.put(opts, :send_body, :stream))

    defp request(method, url, headers, body, opts) when is_function(body),
      do: do_request(method, url, headers, body, Map.put(opts, :send_body, :stream))

    defp request(method, url, headers, %Multipart{} = mp, opts) do
      headers = headers ++ Multipart.headers(mp)
      body = Multipart.body(mp)

      do_request(method, url, headers, body, Map.put(opts, :send_body, :stream))
    end

    defp request(method, url, headers, body, opts),
      do: do_request(method, url, headers, body, opts)

    defp do_request(method, url, headers, body, opts) do
      uri = URI.parse(url)
      path = Tesla.Adapter.Shared.prepare_path(uri.path, uri.query)

      with {:ok, pid, opts} <- open_conn(uri, opts) do
        stream = open_stream(pid, method, path, headers, body, opts)
        response = read_response(pid, stream, opts)

        if opts[:close_conn] and opts[:body_as] not in [:stream, :chunks] do
          close(pid)
        end

        response
      end
    end

    @dialyzer [{:nowarn_function, open_conn: 2}, :no_match]
    defp open_conn(%{scheme: scheme, host: host, port: port}, %{conn: conn} = opts)
         when is_pid(conn) do
      info = :gun.info(conn)

      conn_scheme =
        case info do
          # gun master branch support, which has `origin_scheme` in connection info
          %{origin_scheme: scheme} ->
            scheme

          %{transport: :tls} ->
            "https"

          _ ->
            "http"
        end

      conn_host =
        case :inet.ntoa(info.origin_host) do
          {:error, :einval} -> info.origin_host
          ip -> ip
        end

      if conn_scheme == scheme and to_string(conn_host) == host and info.origin_port == port do
        {:ok, conn, Map.put(opts, :receive, false)}
      else
        {:error, :invalid_conn}
      end
    end

    defp open_conn(uri, opts) do
      opts = maybe_add_transport(uri, opts)

      tls_opts =
        if uri.scheme == "https" do
          opts
          |> fetch_tls_opts()
          |> maybe_add_verify_options(opts, uri)
        else
          []
        end

      gun_opts = Map.take(opts, @gun_keys)

      with {:ok, conn} <- do_open_conn(uri, opts, gun_opts, tls_opts) do
        {:ok, conn, opts}
      end
    end

    # In case of a proxy being used the transport opt for initial gun open must be in accordance with the proxy host and port
    # and not force TLS
    defp maybe_add_transport(_, %{proxy: proxy_opts} = opts) when not is_nil(proxy_opts), do: opts
    defp maybe_add_transport(%URI{scheme: "https"}, opts), do: Map.put(opts, :transport, :tls)
    defp maybe_add_transport(_, opts), do: opts

    # Support for gun master branch where transport_opts, were splitted to tls_opts and tcp_opts
    # https://github.com/ninenines/gun/blob/491ddf58c0e14824a741852fdc522b390b306ae2/doc/src/manual/gun.asciidoc#changelog
    # TODO: remove after update to gun 2.0
    defp fetch_tls_opts(%{tls_opts: tls_opts}) when is_list(tls_opts), do: tls_opts
    defp fetch_tls_opts(%{transport_opts: tls_opts}) when is_list(tls_opts), do: tls_opts
    defp fetch_tls_opts(_), do: []

    defp maybe_add_verify_options(tls_opts, %{certificates_verification: true}, %{host: host}) do
      charlist =
        host
        |> to_charlist()
        |> :idna.encode()

      security_opts = [
        verify: :verify_peer,
        cacertfile: CAStore.file_path(),
        depth: 20,
        reuse_sessions: false,
        verify_fun: {&:ssl_verify_hostname.verify_fun/3, [check_hostname: charlist]}
      ]

      Keyword.merge(security_opts, tls_opts)
    end

    defp maybe_add_verify_options(tls_opts, _, _), do: tls_opts

    @dialyzer [{:nowarn_function, do_open_conn: 4}, :no_match]
    defp do_open_conn(uri, %{proxy: {proxy_host, proxy_port}} = opts, gun_opts, tls_opts) do
      connect_opts =
        uri
        |> tunnel_opts()
        |> tunnel_tls_opts(uri.scheme, tls_opts)
        |> add_proxy_auth_credentials(opts)

      with {:ok, pid} <- :gun.open(proxy_host, proxy_port, gun_opts),
           {:ok, _} <- :gun.await_up(pid),
           stream <- :gun.connect(pid, connect_opts),
           {:response, :fin, 200, _} <- :gun.await(pid, stream) do
        {:ok, pid}
      else
        {:response, :nofin, 403, _} -> {:error, :unauthorized}
        {:response, :nofin, 407, _} -> {:error, :proxy_auth_failed}
        error -> error
      end
    end

    defp do_open_conn(
           uri,
           %{proxy: {proxy_type, proxy_host, proxy_port}} = opts,
           gun_opts,
           tls_opts
         ) do
      version =
        proxy_type
        |> to_string()
        |> String.last()
        |> case do
          "4" -> 4
          _ -> 5
        end

      socks_opts =
        uri
        |> tunnel_opts()
        |> tunnel_tls_opts(uri.scheme, tls_opts)
        |> Map.put(:version, version)
        |> add_socks_proxy_auth_credentials(opts)

      gun_opts =
        gun_opts
        |> Map.put(:protocols, [:socks])
        |> Map.update(:socks_opts, socks_opts, &Map.merge(socks_opts, &1))

      with {:ok, pid} <- :gun.open(proxy_host, proxy_port, gun_opts),
           {:ok, _} <- :gun.await_up(pid) do
        {:ok, pid}
      else
        {:error, {:options, {:protocols, [:socks]}}} ->
          {:error, "socks protocol is not supported"}

        error ->
          error
      end
    end

    defp do_open_conn(uri, opts, gun_opts, tls_opts) do
      tcp_opts = Map.get(opts, :tcp_opts, [])

      # if gun used from master
      opts_with_master_keys =
        gun_opts
        |> Map.put(:tls_opts, tls_opts)
        |> Map.put(:tcp_opts, tcp_opts)

      host = domain_or_ip(uri.host)

      with {:ok, pid} <- gun_open(host, uri.port, opts_with_master_keys, opts) do
        {:ok, pid}
      else
        {:error, {:options, {key, _}}} when key in [:tcp_opts, :tls_opts] ->
          gun_open(host, uri.port, Map.put(gun_opts, :transport_opts, tls_opts), opts)

        error ->
          error
      end
    end

    @dialyzer [{:nowarn_function, gun_open: 4}, :no_match]
    defp gun_open(host, port, gun_opts, opts) do
      with {:ok, pid} <- :gun.open(host, port, gun_opts),
           {_, true, _} <- {:receive, opts[:receive], pid},
           {_, {:ok, _}, _} <- {:up, :gun.await_up(pid), pid} do
        {:ok, pid}
      else
        {:receive, false, pid} ->
          {:ok, pid}

        {:up, error, pid} ->
          close(pid)
          error

        error ->
          error
      end
    end

    defp tunnel_opts(uri) do
      host = domain_or_ip(uri.host)
      %{host: host, port: uri.port}
    end

    defp tunnel_tls_opts(opts, "https", tls_opts) do
      http2_opts = %{protocols: [:http2], transport: :tls, tls_opts: tls_opts}
      Map.merge(opts, http2_opts)
    end

    defp tunnel_tls_opts(opts, _, _), do: opts

    defp add_proxy_auth_credentials(opts, %{proxy_auth: {username, password}})
         when is_binary(username) and is_binary(password),
         do: Map.merge(opts, %{username: username, password: password})

    defp add_proxy_auth_credentials(opts, _), do: opts

    defp add_socks_proxy_auth_credentials(opts, %{proxy_auth: {username, password}})
         when is_binary(username) and is_binary(password),
         do: Map.put(opts, :auth, {:username_password, username, password})

    defp add_socks_proxy_auth_credentials(opts, _), do: opts

    defp open_stream(pid, method, path, headers, body, opts) do
      req_opts = %{reply_to: opts[:reply_to] || self()}

      open_stream(pid, method, path, headers, body, req_opts, opts[:send_body])
    end

    defp open_stream(pid, method, path, headers, body, req_opts, :stream) do
      stream = :gun.request(pid, method, path, headers, "", req_opts)
      for data <- body, do: :ok = :gun.data(pid, stream, :nofin, data)
      :gun.data(pid, stream, :fin, "")
      stream
    end

    defp open_stream(pid, method, path, headers, body, req_opts, :at_once),
      do: :gun.request(pid, method, path, headers, body, req_opts)

    defp read_response(pid, stream, opts) do
      receive? = opts[:receive]

      receive do
        {:gun_response, ^pid, ^stream, :fin, status, headers} ->
          {:ok, status, headers, ""}

        {:gun_response, ^pid, ^stream, :nofin, status, headers} ->
          format_response(pid, stream, opts, status, headers, opts[:body_as])

        {:gun_up, ^pid, _protocol} when receive? ->
          read_response(pid, stream, opts)

        {:gun_error, ^pid, reason} ->
          {:error, reason}

        {:gun_down, ^pid, _, _, _, _} when receive? ->
          read_response(pid, stream, opts)

        {:DOWN, _, _, _, reason} ->
          {:error, reason}
      after
        opts[:timeout] || @default_timeout ->
          {:error, :recv_response_timeout}
      end
    end

    defp format_response(pid, stream, opts, status, headers, :plain) do
      case read_body(pid, stream, opts) do
        {:ok, body} ->
          {:ok, status, headers, body}

        {:error, error} ->
          # prevent gun sending messages to owner process, if body is too large and connection is not closed
          :ok = :gun.flush(stream)

          {:error, error}
      end
    end

    defp format_response(pid, stream, opts, status, headers, :stream) do
      stream_body =
        Stream.resource(
          fn -> %{pid: pid, stream: stream} end,
          fn
            %{pid: pid, stream: stream} ->
              case read_chunk(pid, stream, opts) do
                {:nofin, part} -> {[part], %{pid: pid, stream: stream}}
                {:fin, body} -> {[body], %{pid: pid, final: :fin}}
              end

            %{pid: pid, final: :fin} ->
              {:halt, %{pid: pid}}
          end,
          fn %{pid: pid} ->
            if opts[:close_conn], do: close(pid)
          end
        )

      {:ok, status, headers, stream_body}
    end

    defp format_response(pid, stream, opts, status, headers, :chunks) do
      {:ok, status, headers, %{pid: pid, stream: stream, opts: Enum.into(opts, [])}}
    end

    defp read_body(pid, stream, opts, acc \\ "") do
      limit = opts[:max_body]

      receive do
        {:gun_data, ^pid, ^stream, :fin, body} ->
          check_body_size(acc, body, limit)

        {:gun_data, ^pid, ^stream, :nofin, part} ->
          with {:ok, acc} <- check_body_size(acc, part, limit) do
            read_body(pid, stream, opts, acc)
          end

        {:DOWN, _, _, _, reason} ->
          {:error, reason}
      after
        opts[:timeout] || @default_timeout ->
          {:error, :recv_body_timeout}
      end
    end

    defp check_body_size(acc, part, nil), do: {:ok, acc <> part}

    defp check_body_size(acc, part, limit) do
      body = acc <> part

      if limit - byte_size(body) >= 0 do
        {:ok, body}
      else
        {:error, :body_too_large}
      end
    end

    defp domain_or_ip(host) do
      charlist = to_charlist(host)

      case :inet.parse_address(charlist) do
        {:error, :einval} ->
          :idna.encode(charlist)

        {:ok, ip} ->
          ip
      end
    end
  end
end
