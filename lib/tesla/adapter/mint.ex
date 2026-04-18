if Code.ensure_loaded?(Mint.HTTP) do
  defmodule Tesla.Adapter.Mint do
    @moduledoc """
    Adapter for [mint](https://github.com/elixir-mint/mint).

    **NOTE:** The minimum supported Elixir version for mint is 1.5.0

    Remember to add `{:mint, "~> 1.0"}` and `{:castore, "~> 0.1"}` to dependencies.
    Also, you need to recompile tesla after adding `:mint` dependency:

    ```shell
    mix deps.clean tesla
    mix deps.compile tesla
    ```

    ## Examples

    ```elixir
    # set globally in config/config.exs
    config :tesla, :adapter, Tesla.Adapter.Mint
    # set per module
    defmodule MyClient do
      def client do
        Tesla.client([], Tesla.Adapter.Mint)
      end
    end

    # set global custom cacertfile
    config :tesla, adapter: {Tesla.Adapter.Mint, cacert: ["path_to_cacert"]}
    ```

    ## Adapter specific options:

    - `:timeout` - Time in milliseconds, while process, will wait for mint messages. Defaults to `2_000`.
    - `:body_as` - What will be returned in `%Tesla.Env{}` body key. Possible values - `:plain`, `:stream`, `:chunks`. Defaults to `:plain`.
      - `:plain` - as binary.
      - `:stream` - as stream. If you don't want to close connection (because you want to reuse it later) pass `close_conn: false` in adapter opts.
      - `:chunks` - as chunks. You can get response body in chunks using `Tesla.Adapter.Mint.read_chunk/3` function.
      Processing of the chunks and checking body size must be done by yourself. Example of processing function is in `test/tesla/adapter/mint_test.exs` - `Tesla.Adapter.MintTest.read_body/4`. If you don't need connection later don't forget to close it with `Tesla.Adapter.Mint.close/1`.
    - `:max_body` - Max response body size in bytes. Works only with `body_as: :plain`, with other settings you need to check response body size by yourself.
    - `:conn` - Opened connection with mint. Is used for reusing mint connections.
    - `:mode` - Mint receive mode. Defaults to `:passive` for connections opened by the adapter. When reusing a caller-supplied `:conn`, pass `:mode` explicitly if that connection is not `:active`.
    - `:original` - Original host with port, for which reused connection was open. Needed for `Tesla.Middleware.FollowRedirects`. Otherwise adapter will use connection for another open host.
    - `:close_conn` - Close connection or not after receiving full response body. Is used for reusing mint connections. Defaults to `true`.
    - `:proxy` - Proxy settings. E.g.: `{:http, "localhost", 8888, []}`, `{:http, "127.0.0.1", 8888, []}`
    - `:transport_opts` - Keyword list of HTTP or HTTPS options passed into `:gen_tcp` or `:ssl` respectively by mint. See [mint's docs on `transport_opts`](https://hexdocs.pm/mint/Mint.HTTP.html#connect/4-transport-options).
    """

    @behaviour Tesla.Adapter

    import Tesla.Adapter.Shared
    alias Tesla.Multipart
    alias Mint.HTTP

    @default timeout: 2_000, body_as: :plain, close_conn: true
    @http2_request_chunk_size 16_384

    @tags [:tcp_error, :ssl_error, :tcp_closed, :ssl_closed, :tcp, :ssl]

    @impl Tesla.Adapter
    def call(env, opts) do
      opts = Tesla.Adapter.opts(@default, env, opts)

      with {:ok, status, headers, body} <- request(env, opts) do
        {:ok, %{env | status: status, headers: headers, body: body}}
      end
    end

    @doc """
    Reads chunk of the response body.
    Returns `{:fin, HTTP.t(), binary()}` if all body received, otherwise returns `{:nofin, HTTP.t(), binary()}`.
    """

    @spec read_chunk(HTTP.t(), reference(), keyword()) ::
            {:fin, HTTP.t(), binary()} | {:nofin, HTTP.t(), binary()}
    def read_chunk(conn, ref, opts) do
      with {:ok, conn, acc} <- receive_packet(conn, ref, Enum.into(opts, %{})),
           {state, data} <- response_state(acc) do
        {:ok, conn} =
          if state == :fin and opts[:close_conn] do
            close(conn)
          else
            {:ok, conn}
          end

        {state, conn, data}
      end
    end

    @doc """
    Closes mint connection.
    """
    @spec close(HTTP.t()) :: {:ok, HTTP.t()}
    defdelegate close(conn), to: HTTP

    defp request(env, opts) do
      request(
        format_method(env.method),
        Tesla.build_url(env),
        env.headers,
        env.body,
        Enum.into(opts, %{})
      )
    end

    defp request(method, url, headers, %Stream{} = body, opts) do
      fun = stream_to_fun(body)
      request(method, url, headers, fun, opts)
    end

    defp request(method, url, headers, %Multipart{} = body, opts) do
      headers = headers ++ Multipart.headers(body)
      fun = stream_to_fun(Multipart.body(body))
      request(method, url, headers, fun, opts)
    end

    defp request(method, url, headers, body, opts),
      do: do_request(method, url, headers, body, opts)

    defp do_request(method, url, headers, body, opts) do
      with uri <- URI.parse(url),
           path <- prepare_path(uri.path, uri.query),
           opts <- check_original(uri, opts),
           {:ok, conn, opts} <- open_conn(uri, opts),
           {:ok, conn, ref, response} <- make_request(conn, method, path, headers, body, opts) do
        format_response(conn, ref, opts, response)
      end
    end

    defp check_original(uri, %{original: original} = opts) do
      Map.put(opts, :original_matches, original == "#{uri.host}:#{uri.port}")
    end

    defp check_original(_uri, opts), do: opts

    defp open_conn(_uri, %{conn: conn, original_matches: true} = opts) do
      opts = Map.put_new(opts, :mode, :active)

      with {:ok, conn} <- HTTP.set_mode(conn, opts[:mode]) do
        {:ok, conn, opts}
      end
    end

    defp open_conn(uri, %{conn: conn, original_matches: false} = opts) do
      opts =
        opts
        |> Map.put_new(:old_conn, conn)
        |> Map.delete(:conn)

      open_conn(uri, opts)
    end

    defp open_conn(uri, opts) do
      opts =
        with "https" <- uri.scheme,
             global_cacertfile when not is_nil(global_cacertfile) <-
               Application.get_env(:tesla, Tesla.Adapter.Mint)[:cacert] do
          Map.update(opts, :transport_opts, [cacertfile: global_cacertfile], fn tr_opts ->
            Keyword.put_new(tr_opts, :cacertfile, global_cacertfile)
          end)
        else
          _ -> opts
        end

      opts = Map.put_new(opts, :mode, :passive)

      with {:ok, conn} <-
             HTTP.connect(String.to_atom(uri.scheme), uri.host, uri.port, Enum.into(opts, [])) do
        # If there were redirects, and passed `closed_conn: false`, we need to close opened connections to these intermediate hosts.
        {:ok, conn, Map.put(opts, :close_conn, true)}
      end
    end

    defp make_request(conn, method, path, headers, body, opts) when is_function(body) do
      with {:ok, conn, ref} <-
             HTTP.request(
               conn,
               method,
               path,
               headers,
               :stream
             ),
           {:ok, conn, response} <- stream_request(conn, ref, body, opts) do
        {:ok, conn, ref, response}
      end
    end

    defp make_request(conn, method, path, headers, body, opts)
         when is_binary(body) or is_list(body) do
      body_length = IO.iodata_length(body)

      if HTTP.protocol(conn) == :http2 and body_length > 0 do
        headers = put_default_content_length_header(headers, body_length)
        make_request(conn, method, path, headers, stream_to_fun(iodata_stream(body)), opts)
      else
        case HTTP.request(conn, method, path, headers, body) do
          {:ok, conn, ref} ->
            {:ok, conn, ref, %{}}

          {:error, _conn, error} ->
            {:error, error}
        end
      end
    end

    defp make_request(conn, method, path, headers, body, _opts) do
      case HTTP.request(conn, method, path, headers, body) do
        {:ok, conn, ref} ->
          {:ok, conn, ref, %{}}

        {:error, _conn, error} ->
          {:error, error}
      end
    end

    defp stream_request(conn, ref, fun, opts, acc \\ %{}) do
      case next_chunk(fun) do
        {:ok, item, fun} ->
          with {:ok, conn, acc} <- stream_request_body(conn, ref, item, opts, acc) do
            stream_request(conn, ref, fun, opts, acc)
          end

        :eof ->
          case HTTP.stream_request_body(conn, ref, :eof) do
            {:ok, conn} -> {:ok, conn, acc}
            {:error, _conn, error} -> {:error, error}
          end
      end
    end

    defp format_response(conn, ref, %{body_as: :plain} = opts, response) do
      with {:ok, response} <- receive_responses(conn, ref, opts, response) do
        {:ok, response[:status], response[:headers], response[:data]}
      end
    end

    defp format_response(conn, ref, %{body_as: :chunks} = opts, response) do
      with {:ok, conn, %{status: status, headers: headers} = acc} <-
             receive_headers_and_status(conn, ref, opts, response),
           {state, data} <-
             response_state(acc) do
        {:ok, conn} =
          if state == :fin and opts[:close_conn] do
            close(conn)
          else
            {:ok, conn}
          end

        {:ok, status, headers, %{conn: conn, ref: ref, opts: opts, body: {state, data}}}
      end
    end

    defp format_response(conn, ref, %{body_as: :stream} = opts, response) do
      # there can be some data already
      with {:ok, conn, %{status: status, headers: headers} = acc} <-
             receive_headers_and_status(conn, ref, opts, response) do
        body_as_stream =
          Stream.resource(
            fn -> %{conn: conn, data: acc[:data], done: acc[:done]} end,
            fn
              %{conn: conn, data: data, done: true} ->
                {[data], %{conn: conn, is_fin: true}}

              %{conn: conn, data: data} when is_binary(data) ->
                {[data], %{conn: conn}}

              %{conn: conn, is_fin: true} ->
                {:halt, %{conn: conn}}

              %{conn: conn} ->
                case receive_packet(conn, ref, opts) do
                  {:ok, conn, %{done: true, data: data}} ->
                    {[data], %{conn: conn, is_fin: true}}

                  {:ok, conn, %{done: true}} ->
                    {[], %{conn: conn, is_fin: true}}

                  {:ok, conn, %{data: data}} ->
                    {[data], %{conn: conn}}

                  {:ok, conn, _} ->
                    {[], %{conn: conn}}

                  {:error, error} ->
                    raise_stream_error(error)
                end
            end,
            fn %{conn: conn} -> if opts[:close_conn], do: {:ok, _conn} = close(conn) end
          )

        {:ok, status, headers, body_as_stream}
      end
    end

    defp receive_responses(conn, ref, opts, acc) do
      with {:ok, conn, acc} <- receive_packet(conn, ref, opts, acc),
           :ok <- check_data_size(acc, conn, opts) do
        if acc[:done] do
          if opts[:close_conn], do: {:ok, _conn} = close(conn)
          {:ok, acc}
        else
          receive_responses(conn, ref, opts, acc)
        end
      end
    end

    defp check_data_size(%{data: data}, conn, %{max_body: max_body} = opts)
         when is_binary(data) do
      if max_body - byte_size(data) >= 0 do
        :ok
      else
        if opts[:close_conn], do: {:ok, _conn} = close(conn)
        {:error, :body_too_large}
      end
    end

    defp check_data_size(_, _, _), do: :ok

    defp receive_headers_and_status(conn, ref, opts, acc) do
      with {:ok, conn, acc} <- receive_packet(conn, ref, opts, acc) do
        case acc do
          %{status: _status, headers: _headers} -> {:ok, conn, acc}
          # if we don't have status or headers we try to get them in next packet
          _ -> receive_headers_and_status(conn, ref, opts, acc)
        end
      end
    end

    defp response_state(%{done: true, data: data}), do: {:fin, data}
    defp response_state(%{data: data}), do: {:nofin, data}
    defp response_state(%{done: true}), do: {:fin, ""}
    defp response_state(_), do: {:nofin, ""}

    defp receive_packet(conn, ref, opts, acc \\ %{}) do
      with {:ok, conn, responses} <- receive_message(conn, opts),
           {:ok, acc} <- reduce_responses(responses, ref, acc) do
        {:ok, conn, acc}
      else
        {:error, error} ->
          if opts[:close_conn], do: {:ok, _conn} = close(conn)
          {:error, error}

        {:error, conn, %Mint.TransportError{reason: :timeout}, _res} ->
          if opts[:close_conn], do: {:ok, _conn} = close(conn)
          {:error, :timeout}

        {:error, conn, error, _res} ->
          if opts[:close_conn], do: {:ok, _conn} = close(conn)
          # TODO: (breaking change) fix typo in error message, "Encounter" => "Encountered"
          {:error, "Encounter Mint error #{inspect(error)}"}

        :unknown ->
          if opts[:close_conn], do: {:ok, _conn} = close(conn)
          {:error, :unknown}
      end
    end

    defp receive_message(conn, %{mode: :active} = opts) do
      receive do
        message when is_tuple(message) and elem(message, 0) in @tags ->
          HTTP.stream(conn, message)
      after
        opts[:timeout] -> {:error, :timeout}
      end
    end

    defp receive_message(conn, %{mode: :passive} = opts),
      do: HTTP.recv(conn, 0, opts[:timeout])

    defp raise_stream_error(error) when Kernel.is_exception(error), do: raise(error)
    defp raise_stream_error(error) when is_binary(error), do: raise(RuntimeError, message: error)
    defp raise_stream_error(error), do: raise(RuntimeError, message: inspect(error))

    defp put_default_content_length_header(headers, body_length) do
      if Enum.any?(headers, fn {name, _value} -> String.downcase(name) == "content-length" end) do
        headers
      else
        [{"content-length", Integer.to_string(body_length)} | headers]
      end
    end

    defp iodata_stream(body) do
      Stream.resource(
        fn -> {[body], [], 0} end,
        &next_iodata_chunk/1,
        fn _ -> :ok end
      )
    end

    defp next_iodata_chunk({[], [], 0}), do: {:halt, {[], [], 0}}

    defp next_iodata_chunk({[], buffer, _buffer_size}) do
      {[IO.iodata_to_binary(Enum.reverse(buffer))], {[], [], 0}}
    end

    defp next_iodata_chunk({[chunk | rest], buffer, buffer_size}) when is_binary(chunk) do
      chunk_size = byte_size(chunk)

      cond do
        buffer_size == 0 and chunk_size > @http2_request_chunk_size ->
          <<head::binary-size(@http2_request_chunk_size), tail::binary>> = chunk
          {[head], {[tail | rest], [], 0}}

        buffer_size + chunk_size < @http2_request_chunk_size ->
          next_iodata_chunk({rest, [chunk | buffer], buffer_size + chunk_size})

        true ->
          take_size = @http2_request_chunk_size - buffer_size
          <<head::binary-size(take_size), tail::binary>> = chunk
          chunk = IO.iodata_to_binary(Enum.reverse([head | buffer]))
          {[chunk], {[tail | rest], [], 0}}
      end
    end

    defp next_iodata_chunk({[chunk | rest], buffer, buffer_size})
         when is_integer(chunk) and chunk >= 0 and chunk <= 255 do
      if buffer_size + 1 < @http2_request_chunk_size do
        next_iodata_chunk({rest, [chunk | buffer], buffer_size + 1})
      else
        chunk = IO.iodata_to_binary(Enum.reverse([chunk | buffer]))
        {[chunk], {rest, [], 0}}
      end
    end

    defp next_iodata_chunk({[chunk | rest], buffer, buffer_size}) when is_list(chunk) do
      next_iodata_chunk({prepend_iodata(chunk, rest), buffer, buffer_size})
    end

    defp next_iodata_chunk({[chunk | _rest], _buffer, _buffer_size}) do
      IO.iodata_to_binary([chunk])
    end

    defp prepend_iodata([], rest), do: rest
    defp prepend_iodata([head | tail], rest), do: [head | prepend_iodata(tail, rest)]

    defp stream_request_body(conn, ref, chunk, opts, acc) when is_binary(chunk) do
      stream_request_body_chunk(conn, ref, chunk, opts, acc)
    end

    defp stream_request_body(conn, ref, chunk, opts, acc)
         when is_integer(chunk) and chunk >= 0 and chunk <= 255 do
      stream_request_body_chunk(conn, ref, <<chunk>>, opts, acc)
    end

    defp stream_request_body(conn, ref, chunk, opts, acc) when is_list(chunk) do
      Enum.reduce_while(iodata_stream(chunk), {:ok, conn, acc}, fn item, {:ok, conn, acc} ->
        case stream_request_body(conn, ref, item, opts, acc) do
          {:ok, conn, acc} -> {:cont, {:ok, conn, acc}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end

    defp stream_request_body(conn, ref, chunk, opts, acc) do
      chunk
      |> IO.iodata_to_binary()
      |> then(&stream_request_body_chunk(conn, ref, &1, opts, acc))
    end

    defp stream_request_body_chunk(conn, _ref, "", _opts, acc), do: {:ok, conn, acc}

    defp stream_request_body_chunk(conn, ref, chunk, opts, acc) do
      case HTTP.protocol(conn) do
        :http2 ->
          stream_http2_body_chunk(
            conn,
            ref,
            chunk,
            opts,
            acc,
            min(byte_size(chunk), @http2_request_chunk_size)
          )

        _ ->
          case HTTP.stream_request_body(conn, ref, chunk) do
            {:ok, conn} -> {:ok, conn, acc}
            {:error, _conn, error} -> {:error, error}
          end
      end
    end

    defp stream_http2_body_chunk(conn, _ref, "", _opts, acc, _chunk_size), do: {:ok, conn, acc}

    defp stream_http2_body_chunk(conn, ref, chunk, opts, acc, chunk_size) do
      chunk_size = min(byte_size(chunk), chunk_size)
      <<body_chunk::binary-size(chunk_size), rest::binary>> = chunk

      case HTTP.stream_request_body(conn, ref, body_chunk) do
        {:ok, conn} ->
          stream_http2_body_chunk(
            conn,
            ref,
            rest,
            opts,
            acc,
            min(byte_size(rest), @http2_request_chunk_size)
          )

        {:error, conn, %Mint.HTTPError{reason: {:exceeds_window_size, _, 0}}} ->
          await_request_window(conn, ref, chunk, opts, acc, chunk_size)

        {:error, conn, %Mint.HTTPError{reason: {:exceeds_window_size, _, window_size}}} ->
          stream_http2_body_chunk(conn, ref, chunk, opts, acc, window_size)

        {:error, _conn, error} ->
          {:error, error}
      end
    end

    defp await_request_window(conn, ref, chunk, opts, acc, chunk_size) do
      with {:ok, conn, acc} <- receive_packet(conn, ref, opts, acc) do
        stream_http2_body_chunk(conn, ref, chunk, opts, acc, chunk_size)
      end
    end

    defp reduce_responses(responses, ref, acc) do
      case Enum.reduce_while(responses, acc, &reduce_response(&1, ref, &2)) do
        {:error, _} = error -> error
        acc -> {:ok, acc}
      end
    end

    defp reduce_response({:status, response_ref, code}, ref, acc) when response_ref == ref,
      do: {:cont, Map.put(acc, :status, code)}

    defp reduce_response({:headers, response_ref, headers}, ref, acc) when response_ref == ref,
      do: {:cont, Map.update(acc, :headers, headers, &(&1 ++ headers))}

    defp reduce_response({:data, response_ref, data}, ref, acc) when response_ref == ref,
      do: {:cont, Map.update(acc, :data, data, &(&1 <> data))}

    defp reduce_response({:done, response_ref}, ref, acc) when response_ref == ref,
      do: {:cont, Map.put(acc, :done, true)}

    defp reduce_response({:error, response_ref, error}, ref, _acc) when response_ref == ref,
      do: {:halt, {:error, error}}

    defp reduce_response({:pong, response_ref}, ref, acc) when response_ref == ref,
      do: {:cont, acc}

    defp reduce_response({:status, _other_ref, _code}, _ref, acc), do: {:cont, acc}
    defp reduce_response({:headers, _other_ref, _headers}, _ref, acc), do: {:cont, acc}
    defp reduce_response({:data, _other_ref, _data}, _ref, acc), do: {:cont, acc}
    defp reduce_response({:done, _other_ref}, _ref, acc), do: {:cont, acc}
    defp reduce_response({:error, _other_ref, _error}, _ref, acc), do: {:cont, acc}
    defp reduce_response({:pong, _other_ref}, _ref, acc), do: {:cont, acc}

    defp reduce_response({:push_promise, _parent_ref, _promised_ref, _headers}, _ref, acc),
      do: {:cont, acc}
  end
end
