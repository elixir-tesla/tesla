defmodule Tesla do
  defmacro __using__(_what) do
    quote do
      def get(url),   do: request(:get,  url)
      def post(url),  do: request(:post,  url)

      defp request(method, url) do
        call(%Tesla.Env{
          method: method,
          url:    url
        })
      end

      import Tesla

      Module.register_attribute(__MODULE__, :middleware, accumulate: true)
      @before_compile Tesla
    end
  end

  defmacro __before_compile__(env) do
    adapter = Module.get_attribute(env.module, :adapter)
    if adapter == nil do
      raise "You need to specify adapter"
    end


    middleware = Module.get_attribute(env.module, :middleware)

    reduced = Enum.reduce(middleware, (quote do: exec(env)), fn {mid, args}, acc ->
      quote do
        unquote(mid).call(env, fn(env) -> unquote(acc) end, unquote(args))
      end
    end)

    quote do
      def call(env) do
        unquote(reduced)
      end

      def exec(env) do
        unquote(adapter).call(env)
      end
    end
  end

  defmacro adapter(ad) do
    quote do
      @adapter unquote(ad)
    end
  end

  defmacro with(middleware) do
    quote do
      @middleware {unquote(middleware), []}
    end
  end

  defmacro with(middleware, args) do
    quote do
      @middleware {unquote(middleware), unquote(args)}
    end
  end
end

defmodule Tesla.Env do
  defstruct url:      "",
            method:   nil
end
