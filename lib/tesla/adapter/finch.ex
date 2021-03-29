if Code.ensure_loaded?(Finch) do
  defmodule Tesla.Adapter.Finch do
    @moduledoc """
    Adapter for [finch](https://github.com/keathley/finch).

    Remember to add `{:finch, "~> 0.3"}` to dependencies. Also, you need to
    recompile tesla after adding the `:finch` dependency:

    ```
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

    ```
    # set globally in config/config.exs
    config :tesla, :adapter, {Tesla.Adapter.Finch, name: MyFinch}

    # set per module
    defmodule MyClient do
      use Tesla

      adapter Tesla.Adapter.Finch, name: MyFinch
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

    @impl Tesla.Adapter
    def call(%Tesla.Env{} = env, opts) do
      opts = Tesla.Adapter.opts(env, opts)

      name = Keyword.fetch!(opts, :name)
      url = Tesla.build_url(env.url, env.query)
      req_opts = Keyword.take(opts, [:pool_timeout, :receive_timeout])

      case request(name, env.method, url, env.headers, env.body, req_opts) do
        {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
          {:ok, %Tesla.Env{env | status: status, headers: headers, body: body}}

        {:error, mint_error} ->
          {:error, Exception.message(mint_error)}
      end
    end

    defp request(name, method, url, headers, %Multipart{} = mp, opts) do
      headers = headers ++ Multipart.headers(mp)
      body = Multipart.body(mp) |> Enum.to_list()

      request(name, method, url, headers, body, opts)
    end

    defp request(_name, _method, _url, _headers, %Stream{}, _opts) do
      raise "Streaming is not supported by this adapter!"
    end

    defp request(name, method, url, headers, body, opts) do
      Finch.build(method, url, headers, body)
      |> Finch.request(name, opts)
    end
  end
end
