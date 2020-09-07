if Code.ensure_loaded(Finch) do
  defmodule Tesla.Adapter.Finch do
    @moduledoc """
    Adapter for [finch](https://hexdocs.pm/finch/Finch.html)

    Remember to add `{:finch,"~> 0.3.1"}` to dependencies (and `:finch` if
    necessary to applications in `mix.exs`). Also, you need to recompile tesla
    after adding `:finch` dependency:

    ```
    mix deps.clean tesla
    mix deps.compile tesla
    ```

    ## Example usage

    In addition to configuring tesla to use this adapter, you need to start
    Finch under your supervision tree:

        [
          {Finch, name: YourClient, pools: %{default: [size: 10]}},
          # ...other children
        ]

    By default, this adapter will attempt to use the pool with the same name as
    your client module, otherwise, specify the `:name` in your `:adapter`
    options. Examples:

        defmodule YourClient do
          use Tesla
          adapter Tesla.Adapter.Finch
          plug Tesla.Middleware.Opts, adapter: [name: YourCustomPool]
        end

        # ~ or ~

        Tesla.get("/foo", opts: [adapter: [name: YourCustomPool]])
    """

    @behaviour Tesla.Adapter

    alias Tesla.Multipart

    import Tesla.Adapter.Shared, only: [format_method: 1]

    @impl Tesla.Adapter
    def call(env, opts) do
      defaults = [name: env.__module__]
      opts = Tesla.Adapter.opts(defaults, env, opts)

      request = build_request(env)

      with {:ok, response} <- Finch.request(request, opts[:name], opts) do
        {:ok, %{env | status: response.status, headers: response.headers, body: response.body}}
      end
    end

    defp build_request(%{body: %Multipart{} = mp} = env) do
      build_request(%{
        env
        | headers: env.headers ++ Multipart.headers(mp),
          body: mp |> Multipart.body() |> Enum.to_list()
      })
    end

    defp build_request(%{body: %s{} = stream} = env) when s in [Stream, File.Stream] do
      build_request(%{env | body: Enum.to_list(stream)})
    end

    defp build_request(%{body: f} = env) when is_function(f) do
      build_request(%{env | body: Enum.to_list(f)})
    end

    defp build_request(env) do
      Finch.build(
        format_method(env.method),
        Tesla.build_url(env.url, env.query),
        env.headers,
        env.body
      )
    end
  end
end
