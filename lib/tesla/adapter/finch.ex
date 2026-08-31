if Code.ensure_loaded?(Finch) do
  defmodule Tesla.Adapter.Finch do
    @moduledoc """
    Adapter for [finch](https://github.com/sneako/finch).

    Remember to add `{:finch, "~> 0.14.0"}` to dependencies. Also, you need to
    recompile tesla after adding the `:finch` dependency:

    ```shell
    mix deps.clean tesla
    mix compile
    ```

    ## Examples

    In order to use Finch, you must start it and provide a `:name`. For example,
    in your supervision tree:

    ```elixir
    children = [
      {Finch, name: MyFinch}
    ]
    ```

    You must provide the same name to this adapter:

    ```elixir
    # set globally in config/config.exs
    config :tesla, :adapter, {Tesla.Adapter.Finch, name: MyFinch}

    # set per module
    defmodule MyClient do
      def client do
        Tesla.client([], {Tesla.Adapter.Finch, name: MyFinch})
      end
    end
    ```

    ## Adapter specific options

      * `:name` - The `:name` provided to Finch (**required**).
      * `:response` - Expected response type. Defines the Finch request type
        to use. Supported values:
        + `:stream` - Streams the response using `Finch.stream/5` for the
          request.
        + `nil` or not specified - Responds without streaming using
          `Finch.request/3`.

    ## Streamed response failures

    When `response: :stream` is used, failures that happen after the response
    headers arrived cannot be returned as `{:error, reason}`, because the
    request already succeeded from the caller point of view. Such failures raise
    `Tesla.Error` while the body stream is being consumed, so that a truncated
    response is never mistaken for a complete one:

    ```elixir
    try do
      Enum.each(env.body, &handle_chunk/1)
    rescue
      e in Tesla.Error ->
        # e.reason is, for example, :closed or :timeout
        {:error, e.reason}
    end
    ```

    Waiting longer than `:receive_timeout` for the next chunk raises with reason
    `:timeout`. A server that ends the response early without failing the
    connection is not an error, and the stream simply ends.

    ## [Finch build options](https://hexdocs.pm/finch/Finch.html#build/5)

      * `:unix_socket` - Path to a Unix domain socket to connect to instead of the
        URL host/port. The URL scheme still determines whether HTTP or HTTPS is used.

      * `:pool_tag` - The tag to use when selecting which pool to use for this request.
        Defaults to `:default`. See [Finch - Pool Tagging](https://hexdocs.pm/finch/Finch.html#module-pool-tagging).

    ## [Finch request options](https://hexdocs.pm/finch/Finch.html#t:request_opt/0)

      * `:pool_timeout` - This timeout is applied when a connection is checked
        out from the pool. Default value is `5_000`.

      * `:receive_timeout` - The maximum time to wait for each chunk to arrive
        before returning an error. Default value is `15_000`.

      * `:request_timeout` - The maximum time to wait for a complete response
        before returning an error. Only applies to HTTP/1. Default value is `:infinity`.

      * `:pool_strategy` - Determines which shard handles the request when the pool
        has multiple shards (`count > 1`). Default selection is random.

    """
    @behaviour Tesla.Adapter
    import Tesla.Adapter.Shared, only: [format_method: 1]
    alias Tesla.Multipart

    @defaults [
      receive_timeout: 15_000
    ]

    @finch_version :finch |> Application.spec(:vsn) |> to_string()

    @impl Tesla.Adapter
    def call(%Tesla.Env{} = env, opts) do
      opts = Tesla.Adapter.opts(@defaults, env, opts)

      name = Keyword.fetch!(opts, :name)
      url = Tesla.build_url(env)

      req_opts =
        Keyword.take(opts, [:pool_timeout, :receive_timeout, :request_timeout, :pool_strategy])

      build_opts = Keyword.take(opts, [:unix_socket, :pool_tag])
      req = build(format_method(env.method), url, env.headers, env.body, build_opts)

      case request(req, name, req_opts, opts, env) do
        {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
          {:ok, %Tesla.Env{env | status: status, headers: headers, body: body}}

        {:error, reason} ->
          {:error, unwrap_error(reason)}
      end
    end

    # Finch v0.22 started wrapping every failure in `Finch.error()`. Unwrap it back to
    # the reasons callers matched on before, so the adapter behaves the same on both.
    defp unwrap_error(error) when is_struct(error, Finch.TransportError), do: error.reason
    defp unwrap_error(error) when is_struct(error, Finch.HTTPError), do: error.source || error

    if Version.match?(@finch_version, "< 0.22.0") do
      defp unwrap_error(%Mint.TransportError{reason: reason}), do: reason
    end

    defp unwrap_error(error), do: error

    defp build(method, url, headers, %Multipart{} = mp, opts) do
      headers = headers ++ Multipart.headers(mp)
      body = Multipart.body(mp)

      build(method, url, headers, body, opts)
    end

    defp build(method, url, headers, %Stream{} = body_stream, opts) do
      build(method, url, headers, {:stream, body_stream}, opts)
    end

    defp build(method, url, headers, body_stream_fun, opts) when is_function(body_stream_fun) do
      build(method, url, headers, {:stream, body_stream_fun}, opts)
    end

    defp build(method, url, headers, body, opts) do
      Finch.build(method, url, headers, body, opts)
    end

    defp request(req, name, req_opts, opts, env) do
      case opts[:response] do
        :stream -> stream(req, name, req_opts, env)
        nil -> Finch.request(req, name, req_opts)
        other -> raise "Unknown response option: #{inspect(other)}"
      end
    end

    defp stream(req, name, opts, env) do
      owner = self()
      ref = make_ref()

      fun = fn
        {:status, status}, _acc -> status
        {:headers, headers}, status -> send(owner, {ref, {:status, status, headers}})
        {:data, data}, _acc -> send(owner, {ref, {:data, data}})
        {:trailers, trailers}, _acc -> trailers
        # No released Finch hands an error to this callback, it reports one through the
        # return value instead. Without these clauses such an entry would raise inside
        # the task and the caller would see a timeout rather than the error.
        # coveralls-ignore-next-line
        {:error, error}, _acc -> send(owner, {ref, {:error, error}})
        # coveralls-ignore-next-line
        {:error, error, _}, _acc -> send(owner, {ref, {:error, error}})
      end

      task =
        Task.async(fn ->
          req
          |> Finch.stream(name, nil, fun, opts)
          |> handle_stream_response(ref, owner)
        end)

      receive do
        {^ref, {:status, status, headers}} ->
          body =
            Stream.unfold(nil, fn _ ->
              receive do
                {^ref, {:data, data}} ->
                  {data, nil}

                {^ref, :eof} ->
                  Task.await(task)
                  nil

                {^ref, {:error, error}} ->
                  Task.shutdown(task, :brutal_kill)
                  raise Tesla.Error, env: env, reason: unwrap_error(error)
              after
                opts[:receive_timeout] ->
                  Task.shutdown(task, :brutal_kill)
                  raise Tesla.Error, env: env, reason: :timeout
              end
            end)

          {:ok, %Finch.Response{status: status, headers: headers, body: body}}

        {^ref, {:error, error}} ->
          Task.shutdown(task, :brutal_kill)
          {:error, error}
      after
        opts[:receive_timeout] ->
          Task.shutdown(task, :brutal_kill)
          {:error, :timeout}
      end
    end

    defp handle_stream_response({:ok, _acc}, ref, owner) do
      send(owner, {ref, :eof})
    end

    if Version.match?(@finch_version, ">= 0.20.0") do
      defp handle_stream_response({:error, error, _acc}, ref, owner) do
        send(owner, {ref, {:error, error}})
      end
    else
      defp handle_stream_response({:error, error}, ref, owner) do
        send(owner, {ref, {:error, error}})
      end
    end
  end
end
