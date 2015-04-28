defmodule Tesla.Env do
  defstruct url:      "",
            method:   nil,
            status:   nil,
            headers:  %{},
            body:     nil,
            opts:     []
end

defmodule Tesla.Builder do
  @http_methods [:get, :head, :delete, :trace, :options, :post, :put, :patch]

  defmacro __using__(_what) do
    method_defs = for method <- [:get, :head, :delete, :trace, :options] do
      quote do
        # 4 args
        def unquote(method)(fun, url, query, opts) when is_function(fun) and is_map(query) do
          request(fun, unquote(method), url, query, nil, opts)
        end

        # 3 args
        def unquote(method)(fun, url, query) when is_function(fun) and is_map(query) do
          request(fun, unquote(method), url, query, nil, [])
        end

        def unquote(method)(fun, url, opts) when is_function(fun) do
          request(fun, unquote(method), url, nil, nil, opts)
        end

        def unquote(method)(url, query, opts) when is_map(query) and is_map(query) do
          request(unquote(method), url, query, nil, opts)
        end

        # 2 args
        def unquote(method)(fun, url) when is_function(fun) do
          request(fun, unquote(method), url, nil, nil, [])
        end

        def unquote(method)(url, query) when is_map(query)  do
          request(unquote(method), url, query, nil, [])
        end

        def unquote(method)(url, opts) do
          request(unquote(method), url, nil, nil, opts)
        end

        # 1 args
        def unquote(method)(url) do
          request(unquote(method), url, nil, nil, [])
        end
      end
    end

    method_defs_with_body = for method <- [:post, :put, :patch] do
      quote do
        # 5 args
        def unquote(method)(fun, url, query, body, opts) when is_function(fun) and is_map(query) do
          request(fun, unquote(method), url, query, body, opts)
        end

        # 4 args
        def unquote(method)(fun, url, query, body) when is_function(fun) and is_map(query) do
          request(fun, unquote(method), url, query, body, [])
        end

        def unquote(method)(fun, url, body, opts) when is_function(fun) do
          request(fun, unquote(method), url, nil, body, opts)
        end

        def unquote(method)(url, query, body, opts) when is_map(query) do
          request(unquote(method), url, query, body, opts)
        end

        # 3 args
        def unquote(method)(fun, url, body) when is_function(fun) do
          request(fun, unquote(method), url, nil, body, [])
        end

        def unquote(method)(url, query, body) when is_map(query)  do
          request(unquote(method), url, query, body, [])
        end

        def unquote(method)(url, body, opts) do
          request(unquote(method), url, nil, body, opts)
        end

        # 2 args
        def unquote(method)(url, body) do
          request(unquote(method), url, nil, body, [])
        end
      end
    end

    quote do
      unquote(method_defs)
      unquote(method_defs_with_body)

      @adapter nil

      defp request(fun, method, url, query, body, opts) when is_function(fun) do
        env = %Tesla.Env{
          method: method,
          url:    Tesla.Builder.append_query_string(url, query),
          body:   body,
          opts:   opts
        }

        fun.(env, &call_middleware/1)
      end

      defp request(method, url, query, body, opts) do
        request(fn (env, run) -> run.(env) end, method, url, query, body, opts)
      end

      defp call_with_adapter(env) do
        case call_adapter(env) do
          {status, headers, body} ->
            %{env | status: status, headers: headers, body: body}
          e -> e
        end
      end

      import Tesla.Builder

      Module.register_attribute(__MODULE__, :middleware, accumulate: true)
      @before_compile Tesla.Builder
    end
  end

  defp generate_call_middleware(env) do
    middleware = Module.get_attribute(env.module, :middleware)

    reduced = Enum.reduce(middleware, (quote do: call_with_adapter(env)), fn {mid, args}, acc ->
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

  defp generate_call_adapter(env) do
    adapter = Module.get_attribute(env.module, :adapter)

    case adapter do
      {:fn, _, _} ->
        quote do
          def call_adapter(env) do
            unquote(adapter).(env)
          end
        end

      mod when is_atom(adapter) ->
        quote do
          def call_adapter(env) do
            Tesla.call_module_adapter(unquote(mod), env)
          end
        end

      _ ->
        quote do
          def call_adapter(env) do
            Tesla.call_module_adapter(Tesla.default_adapter, env)
          end
        end
    end
  end

  defmacro __before_compile__(env) do
    [
      generate_call_adapter(env),
      generate_call_middleware(env)
    ]
  end



  defmacro adapter({:fn, _, _} = ad) do # pattern match for function
    escaped = Macro.escape(ad)
    quote do
      @adapter unquote(escaped)
    end
  end

  defmacro adapter(adapter) do
    quote do
      @adapter unquote(adapter)
    end
  end

  defmacro with(middleware, opts \\ []) do
    quote do
      @middleware {unquote(middleware), unquote(opts)}
    end
  end


  defmacro defwrap(head, do: body) do
    fun_var = Macro.var(:client_fun, __MODULE__)

    head_with_client = case head do
      {:when, ctx1, [{name, ctx2, args} | tl]}  -> {:when, ctx1, [{name, ctx2, [fun_var | args]} | tl]}
      {name, ctx, args}                         -> {:when, ctx,  [{name, ctx,  [fun_var | args]}, {:is_function, ctx, [fun_var]}]}
    end

    body_with_client = Macro.prewalk body, fn (ast) ->
      case ast do
        {fun, ctx, args} when fun in @http_methods -> {fun, ctx, [fun_var | args]}
        other -> other
      end
    end

    def_with_client = quote do
      def unquote(head_with_client) do
        unquote(body_with_client)
      end
    end

    normal = quote do
      def unquote(head) do
        unquote(body)
      end
    end

    [def_with_client, normal]
  end


  # Utility functions
  def append_query_string(url, query) do
    if query do
      query_string = URI.encode_query(query)
      if url |> String.contains?("?") do
        url <> "&" <> query_string
      else
        url <> "?" <> query_string
      end
    else
      url
    end
  end
end


defmodule Tesla do
  use Tesla.Builder

  @adapters [ibrowse: Tesla.Adapter.Ibrowse]

  def build_client(stack) do
    fn (env, run) ->
      f = Enum.reduce(stack, run, fn ({mid, args}, acc) ->
        fn (env) -> mid.call(env, fn(e) -> acc.(e) end, args) end
      end)

      f.(env)
    end
  end

  def call_module_adapter(mod, env) do
    (@adapters[mod] || mod).call(env)
  end

  def default_adapter do
    Application.get_env(:tesla, :adapter) || Tesla.Adapter.Ibrowse
  end
end
