if Code.ensure_loaded?(:fuse) do
  defmodule Tesla.Middleware.Fuse do
    @moduledoc """
    Fuse (https://github.com/jlouis/fuse) middleware

    Remember to add `{:fuse, "~> 2.4"}` to dependencies
    and `:fuse` to applications in `mix.exs`

    Example
        defmodule Myclient do
          use Tesla

          plug Tesla.Middleware.Fuse, opts: {{:standard, 2, 10_000}, {:reset, 60_000}}
        end

    Options:
    - `:name` - fuse name (defaults to module name)
    - `:opts` - fuse options (see fuse docs for reference)
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
      try do
        Tesla.run(env, next)
      rescue
        _error ->
          :fuse.melt(name)
          {:error, :unavailable}
      end
    end
  end
end
