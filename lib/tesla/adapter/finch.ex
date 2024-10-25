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

    ## [Finch options](https://hexdocs.pm/finch/Finch.html#request/3)

      * `:pool_timeout` - This timeout is applied when a connection is checked
        out from the pool. Default value is `5_000`.

      * `:receive_timeout` - The maximum time to wait for a response before
        returning an error. Default value is `15_000`.

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
      req_opts = Keyword.take(opts, [:pool_timeout, :receive_timeout])
      req = build(env.method, url, env.headers, env.body)

      case request(req, name, req_opts, opts) do
        {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
          {:ok, %Tesla.Env{env | status: status, headers: headers, body: body}}

        {:error, %Mint.TransportError{reason: reason}} ->
          {:error, reason}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp build(method, url, headers, %Multipart{} = mp) do
      headers = headers ++ Multipart.headers(mp)
      body = Multipart.body(mp)

      build(method, url, headers, body)
    end

    defp build(method, url, headers, %Stream{} = body_stream) do
      build(method, url, headers, {:stream, body_stream})
    end

    defp build(method, url, headers, body_stream_fun) when is_function(body_stream_fun) do
      build(method, url, headers, {:stream, body_stream_fun})
    end

    defp build(method, url, headers, body) do
      Finch.build(method, url, headers, body)
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
      end

      task =
        Task.async(fn ->
          case Finch.stream(req, name, nil, fun, opts) do
            {:ok, _acc} -> send(owner, {ref, :eof})
            {:error, error} -> send(owner, {ref, {:error, error}})
          end
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
              after
                opts[:receive_timeout] ->
                  Task.shutdown(task, :brutal_kill)
                  nil
              end
            end)

          {:ok, %Finch.Response{status: status, headers: headers, body: body}}
      after
        opts[:receive_timeout] ->
          {:error, :timeout}
      end
    end
  end
end
