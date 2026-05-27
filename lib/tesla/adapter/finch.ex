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
    alias Tesla.Multipart

    @defaults [
      receive_timeout: 15_000
    ]

    @impl Tesla.Adapter
    def call(%Tesla.Env{} = env, opts) do
      opts = Tesla.Adapter.opts(@defaults, env, opts)

      name = Keyword.fetch!(opts, :name)
      url = Tesla.build_url(env)
      req_opts = Keyword.take(opts, [:pool_timeout, :receive_timeout, :request_timeout, :pool_strategy])
      build_opts = Keyword.take(opts, [:unix_socket, :pool_tag])
      req = build(env.method, url, env.headers, env.body, build_opts)

      case request(req, name, req_opts, opts) do
        {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
          {:ok, %Tesla.Env{env | status: status, headers: headers, body: body}}

        {:error, %Mint.TransportError{reason: reason}} ->
          {:error, reason}

        {:error, reason} ->
          {:error, reason}
      end
    end

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

    defp request(req, name, req_opts, opts) do
      case opts[:response] do
        :stream -> stream(req, name, req_opts)
        nil -> Finch.request(req, name, req_opts)
        other -> raise "Unknown response option: #{inspect(other)}"
      end
    end

    defp stream(req, name, opts) do
      owner = self()
      ref = make_ref()

      fun = fn
        {:status, status}, _acc -> status
        {:headers, headers}, status -> send(owner, {ref, {:status, status, headers}})
        {:data, data}, _acc -> send(owner, {ref, {:data, data}})
        {:trailers, trailers}, _acc -> trailers
        # Handle errors passed to callback (e.g., proxy errors like {:proxy, {:unexpected_status, 403}})
        {:error, error}, _acc -> send(owner, {ref, {:error, error}})
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

                {^ref, {:error, _error}} ->
                  Task.shutdown(task, :brutal_kill)
                  nil
              after
                opts[:receive_timeout] ->
                  Task.shutdown(task, :brutal_kill)
                  nil
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

    @finch_version :finch |> Application.spec(:vsn) |> to_string()
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
