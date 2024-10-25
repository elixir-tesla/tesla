if Code.ensure_loaded?(:fuse) do
  defmodule Tesla.Middleware.Fuse do
    @moduledoc """
    Circuit Breaker middleware using [fuse](https://github.com/jlouis/fuse).

    Remember to add `{:fuse, "~> 2.4"}` to dependencies (and `:fuse` to applications in `mix.exs`)
    Also, you need to recompile tesla after adding `:fuse` dependency:

    ```
    mix deps.clean tesla
    mix deps.compile tesla
    ```

    ## Examples

    ```elixir
    defmodule MyClient do
      def client do
        Tesla.client([
          {Tesla.Middleware.Fuse,
            opts: {{:standard, 2, 10_000}, {:reset, 60_000}},
            keep_original_error: true,
            should_melt: fn
              {:ok, %{status: status}} when status in [428, 500, 504] -> true
              {:ok, _} -> false
              {:error, _} -> true
            end,
            mode: :sync}
        ])
      end
    end
    ```

    ## Options

    - `:name` - fuse name (defaults to module name)
    - `:opts` - fuse options (see fuse docs for reference)
    - `:keep_original_error` - boolean to indicate if, in case of melting (based on `should_melt`), it should return the upstream's error or the fixed one `{:error, unavailable}`.
    It's false by default, but it will be true in `2.0.0` version
    - `:should_melt` - function to determine if response should melt the fuse
    - `:mode` - how to query the fuse, which has two values:
      - `:sync` - queries are serialized through the `:fuse_server` process (the default)
      - `:async_dirty` - queries check the fuse state directly, but may not account for recent melts or resets

    ## SASL logger

    fuse library uses [SASL (System Architecture Support Libraries)](http://erlang.org/doc/man/sasl_app.html).

    You can disable its logger output using:

    ```elixir
    config :sasl, sasl_error_logger: :false
    ```

    Read more at [jlouis/fuse#32](https://github.com/jlouis/fuse/issues/32) and [jlouis/fuse#19](https://github.com/jlouis/fuse/issues/19).
    """

    @behaviour Tesla.Middleware

    # options borrowed from https://rokkincat.com/blog/2015-09-24-circuit-breakers-in-elixir/
    # most probably not valid for your use case
    @defaults {{:standard, 2, 10_000}, {:reset, 60_000}}

    @impl Tesla.Middleware
    def call(env, next, opts) do
      opts = opts || []

      context = %{
        name: Keyword.get(opts, :name, env.__module__),
        keep_original_error: Keyword.get(opts, :keep_original_error, false),
        should_melt: Keyword.get(opts, :should_melt, &match?({:error, _}, &1)),
        mode: Keyword.get(opts, :mode, :sync)
      }

      case :fuse.ask(context.name, context.mode) do
        :ok ->
          run(env, next, context)

        :blown ->
          {:error, :unavailable}

        {:error, :not_found} ->
          :fuse.install(context.name, Keyword.get(opts, :opts, @defaults))
          run(env, next, context)
      end
    end

    defp run(env, next, %{
           should_melt: should_melt,
           name: name,
           keep_original_error: keep_original_error
         }) do
      res = Tesla.run(env, next)

      if should_melt.(res) do
        :fuse.melt(name)
        if keep_original_error, do: res, else: {:error, :unavailable}
      else
        res
      end
    end
  end
end
