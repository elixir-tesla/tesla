defmodule Tesla.Env do
  defstruct url:      "",
            method:   nil,
            status:   nil,
            headers:  %{},
            body:     nil,
            opts:     []
end

defmodule Tesla.Builder do
  defmacro __using__(_what) do
    method_defs = for method <- [:get, :head, :delete, :trace, :options] do
      quote do
        def unquote(method)(fun, url, opts) when is_function(fun) do
          request(fun, unquote(method), url, nil, opts)
        end

        def unquote(method)(fun, url) when is_function(fun) do
          request(fun, unquote(method), url, nil, [])
        end

        def unquote(method)(url, opts) do
          request(unquote(method), url, nil, opts)
        end

        def unquote(method)(url) do
          request(unquote(method), url, nil, [])
        end
      end
    end

    method_defs_with_body = for method <- [:post, :put, :patch] do
      quote do
        def unquote(method)(fun, url, body, opts) when is_function(fun) do
          request(fun, unquote(method), url, body, opts)
        end

        def unquote(method)(fun, url, body) when is_function(fun) do
          request(fun, unquote(method), url, body, [])
        end

        def unquote(method)(url, body, opts) do
          request(unquote(method), url, body, opts)
        end

        def unquote(method)(url, body) do
          request(unquote(method), url, body, [])
        end
      end
    end

    quote do
      unquote(method_defs)
      unquote(method_defs_with_body)

      defp request(fun, method, url, body, opts) when is_function(fun) do
        env = %Tesla.Env{
          method: method,
          url:    url,
          body:   body,
          opts:   opts
        }

        fun.(env, &call_middleware/1)
      end

      defp request(method, url, body, opts) do
        request(fn (env, run) -> run.(env) end, method, url, body, opts)
      end

      import Tesla.Builder

      Module.register_attribute(__MODULE__, :middleware, accumulate: true)
      @before_compile Tesla.Builder
    end
  end

  defmacro __before_compile__(env) do
    middleware = Module.get_attribute(env.module, :middleware)

    reduced = Enum.reduce(middleware, (quote do: call_adapter(env)), fn {mid, args}, acc ->
      args = Macro.escape(args)
      quote do
        unquote(mid).call(env, fn(env) -> unquote(acc) end, unquote(args))
      end
    end)

    quote do
      def call_middleware(env) do
        unquote(reduced)
      end
    end
  end

  def process_adapter_response(env, res) do
    case res do
      {status, headers, body} ->
        %{env | status: status, headers: headers, body: body}
      e -> e
    end
  end

  defmacro adapter({:fn, _, _} = ad) do # pattern match for function
    quote do
      def call_adapter(env) do
        Tesla.Builder.process_adapter_response(env, unquote(ad).(env))
      end
    end
  end

  defmacro adapter(adapter) do
    quote do
      def call_adapter(env) do
        Tesla.Builder.process_adapter_response(env, unquote(adapter).call(env))
      end
    end
  end

  defmacro with(middleware, opts \\ []) do
    quote do
      @middleware {unquote(middleware), unquote(opts)}
    end
  end
end


defmodule Tesla do
  use Tesla.Builder
  adapter Tesla.Adapter.Ibrowse

  def build_client(stack) do
    fn (env, run) ->
      f = Enum.reduce(stack, run, fn ({mid, args}, acc) ->
        fn (env) -> mid.call(env, fn(e) -> acc.(e) end, args) end
      end)

      f.(env)
    end
  end

  def start do
    Tesla.Adapter.Ibrowse.start
  end
end
