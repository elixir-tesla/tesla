if Code.ensure_loaded?(:fuse) do
  defmodule Tesla.Middleware.Fuse do
    @behaviour Tesla.Middleware

    @moduledoc """
    Circuit Breaker middleware using [fuse](https://github.com/jlouis/fuse)

    Remember to add `{:fuse, "~> 2.4"}` to dependencies (and `:fuse` to applications in `mix.exs`)
    Also, you need to recompile tesla after adding `:fuse` dependency:

    ```
    mix deps.clean tesla
    mix deps.compile tesla
    ```

    ### Example usage
    ```
    defmodule MyClient do
      use Tesla

      plug Tesla.Middleware.Fuse, opts: {{:standard, 2, 10_000}, {:reset, 60_000}}
    end
    ```

    ### Options
    - `:name` - fuse name (defaults to module name)
    - `:opts` - fuse options (see fuse docs for reference)

    ### SASL logger

    fuse library uses [SASL (System Architecture Support Libraries)](http://erlang.org/doc/man/sasl_app.html).

    You can disable its logger output using:

    ```
    config :sasl, sasl_error_logger: :false
    ```

    Read more at [jlouis/fuse#32](https://github.com/jlouis/fuse/issues/32) and [jlouis/fuse#19](https://github.com/jlouis/fuse/issues/19).
    """

    # options borrowed from http://blog.rokkincat.com/circuit-breakers-in-elixir/
    # most probably not valid for your use case
    @defaults {{:standard, 2, 10_000}, {:reset, 60_000}}

    def call(env, next, opts) do
      opts = opts || []
      name = Keyword.get(opts, :name, env.__module__)

      case :fuse.ask(name, :sync) do
        :ok ->
          run(env, next, name)

        :blown ->
          {:error, :unavailable}

        {:error, :not_found} ->
          :fuse.install(name, Keyword.get(opts, :opts, @defaults))
          run(env, next, name)
      end
    end

    defp run(env, next, name) do
      case Tesla.run(env, next) do
        {:ok, env} ->
          {:ok, env}

        {:error, _reason} ->
          :fuse.melt(name)
          {:error, :unavailable}
      end
    end
  end
end
