defmodule Tesla.Builder do
  @http_verbs ~w(head get delete trace options post put patch)a

  defmacro __using__(opts \\ []) do
    opts = Macro.prewalk(opts, &Macro.expand(&1, __CALLER__))
    docs = Keyword.get(opts, :docs, true)

    quote do
      Module.register_attribute(__MODULE__, :__middleware__, accumulate: true)
      Module.register_attribute(__MODULE__, :__adapter__, [])

      if unquote(docs) do
        @type option ::
                {:method, Tesla.Env.method()}
                | {:url, Tesla.Env.url()}
                | {:query, Tesla.Env.query()}
                | {:headers, Tesla.Env.headers()}
                | {:body, Tesla.Env.body()}
                | {:opts, Tesla.Env.opts()}

        @doc """
        Perform a request using client function

        Options:
        - `:method`   - the request method, one of [:head, :get, :delete, :trace, :options, :post, :put, :patch]
        - `:url`      - either full url e.g. "http://example.com/some/path" or just "/some/path" if using `Tesla.Middleware.BaseUrl`
        - `:query`    - a keyword list of query params, e.g. `[page: 1, per_page: 100]`
        - `:headers`  - a keyworld list of headers, e.g. `[{"content-type", "text/plain"}]`
        - `:body`     - depends on used middleware:
            - by default it can be a binary
            - if using e.g. JSON encoding middleware it can be a nested map
            - if adapter supports it it can be a Stream with any of the above
        - `:opts`     - custom, per-request middleware or adapter options

        Examples:

            ExampleApi.request(method: :get, url: "/users/path")

        You can also use shortcut methods like:

            ExampleApi.get("/users/1")

        or

            myclient |> ExampleApi.post("/users", %{name: "Jon"})
        """
        @spec request(Tesla.Env.client(), [option]) :: Tesla.Env.t()
      else
        @doc false
      end

      def request(%Tesla.Client{} = client, options) do
        Tesla.execute(__MODULE__, client, options)
      end

      if unquote(docs) do
        @doc """
        Perform a request. See `request/2` for available options.
        """
        @spec request([option]) :: Tesla.Env.t()
      else
        @doc false
      end

      def request(options) do
        Tesla.execute(__MODULE__, %Tesla.Client{}, options)
      end

      unquote(generate_http_verbs(opts))

      import Tesla.Builder, only: [plug: 1, plug: 2, adapter: 1, adapter: 2]
      @before_compile Tesla.Builder
    end
  end

  @doc """
  Attach middleware to your API client

  ```ex
  defmodule ExampleApi do
    use Tesla

    # plug middleware module with options
    plug Tesla.Middleware.BaseUrl, "http://api.example.com"
    plug Tesla.Middleware.JSON, engine: Poison

    # plug middleware function
    plug :handle_errors

    # middleware function gets two parameters: Tesla.Env and the rest of middleware call stack
    # and must return Tesla.Env
    def handle_errors(env, next) do
      env
      |> modify_env_before_request
      |> Tesla.run(next)            # run the rest of stack
      |> modify_env_after_request
    end
  end
  """
  defmacro plug(middleware, opts \\ nil) do
    quote do: @__middleware__({
      unquote(Macro.escape(middleware)),
      unquote(Macro.escape(opts)),
      unquote(Macro.escape(__CALLER__))
    })
  end

  @doc """
  Choose adapter for your API client

  ```ex
  defmodule ExampleApi do
    use Tesla

    # set adapter as module
    adapter Tesla.Adapter.Hackney

    # set adapter as function
    adapter :local_adapter

    # set adapter as anonymous function
    adapter fn env ->
      ...
      env
    end


    # adapter function gets Tesla.Env as parameter and must return Tesla.Env
    def local_adapter(env) do
      ...
      env
    end
  end
  """
  defmacro adapter(adapter, opts \\ nil) do
    quote do: @__adapter__({
      unquote(Macro.escape(adapter)),
      unquote(Macro.escape(opts)),
      unquote(Macro.escape(__CALLER__))
    })
  end

  defp generate_http_verbs(opts) do
    only = Keyword.get(opts, :only, @http_verbs)
    except = Keyword.get(opts, :except, [])

    @http_verbs
    |> Enum.filter(&(&1 in only && not &1 in except))
    |> Enum.map(&generate_api(&1, Keyword.get(opts, :docs, true)))
  end

  defp generate_api(method, docs) when method in [:post, :put, :patch] do
    quote do
      if unquote(docs) do
        @doc """
        Perform a #{unquote(method |> to_string |> String.upcase())} request.
        See `request/1` or `request/2` for options definition.

        Example
            myclient |> ExampleApi.#{unquote(method)}("/users", %{name: "Jon"}, query: [scope: "admin"])
        """
        @spec unquote(method)(Tesla.Env.client(), Tesla.Env.url(), Tesla.Env.body(), [option]) ::
                Tesla.Env.t()
      else
        @doc false
      end

      def unquote(method)(%Tesla.Client{} = client, url, body, options) when is_list(options) do
        request(client, [method: unquote(method), url: url, body: body] ++ options)
      end

      # fallback to keep backward compatibility
      def unquote(method)(fun, url, body, options) when is_function(fun) and is_list(options) do
        unquote(method)(%Tesla.Client{fun: fun}, url, body, options)
      end

      if unquote(docs) do
        @doc """
        Perform a #{unquote(method |> to_string |> String.upcase())} request.
        See `request/1` or `request/2` for options definition.

        Example
            myclient |> ExampleApi.#{unquote(method)}("/users", %{name: "Jon"})
            ExampleApi.#{unquote(method)}("/users", %{name: "Jon"}, query: [scope: "admin"])
        """
        @spec unquote(method)(Tesla.Env.client(), Tesla.Env.url(), Tesla.Env.body()) ::
                Tesla.Env.t()
      else
        @doc false
      end

      def unquote(method)(%Tesla.Client{} = client, url, body) do
        request(client, method: unquote(method), url: url, body: body)
      end

      # fallback to keep backward compatibility
      def unquote(method)(fun, url, body) when is_function(fun) do
        unquote(method)(%Tesla.Client{fun: fun}, url, body)
      end

      if unquote(docs) do
        @spec unquote(method)(Tesla.Env.url(), Tesla.Env.body(), [option]) :: Tesla.Env.t()
      else
        @doc false
      end

      def unquote(method)(url, body, options) when is_list(options) do
        request([method: unquote(method), url: url, body: body] ++ options)
      end

      if unquote(docs) do
        @doc """
        Perform a #{unquote(method |> to_string |> String.upcase())} request.
        See `request/1` or `request/2` for options definition.

        Example
            ExampleApi.#{unquote(method)}("/users", %{name: "Jon"})
        """
        @spec unquote(method)(Tesla.Env.url(), Tesla.Env.body()) :: Tesla.Env.t()
      else
        @doc false
      end

      def unquote(method)(url, body) do
        request(method: unquote(method), url: url, body: body)
      end
    end
  end

  defp generate_api(method, docs) when method in [:head, :get, :delete, :trace, :options] do
    quote do
      if unquote(docs) do
        @doc """
        Perform a #{unquote(method |> to_string |> String.upcase())} request.
        See `request/1` or `request/2` for options definition.

        Example
            myclient |> ExampleApi.#{unquote(method)}("/users", query: [page: 1])
        """
        @spec unquote(method)(Tesla.Env.client(), Tesla.Env.url(), [option]) :: Tesla.Env.t()
      else
        @doc false
      end

      def unquote(method)(%Tesla.Client{} = client, url, options) when is_list(options) do
        request(client, [method: unquote(method), url: url] ++ options)
      end

      # fallback to keep backward compatibility
      def unquote(method)(fun, url, options) when is_function(fun) and is_list(options) do
        unquote(method)(%Tesla.Client{fun: fun}, url, options)
      end

      if unquote(docs) do
        @doc """
        Perform a #{unquote(method |> to_string |> String.upcase())} request.
        See `request/1` or `request/2` for options definition.

        Example
            myclient |> ExampleApi.#{unquote(method)}("/users")
            ExampleApi.#{unquote(method)}("/users", query: [page: 1])
        """
        @spec unquote(method)(Tesla.Env.client(), Tesla.Env.url()) :: Tesla.Env.t()
      else
        @doc false
      end

      def unquote(method)(%Tesla.Client{} = client, url) do
        request(client, method: unquote(method), url: url)
      end

      # fallback to keep backward compatibility
      def unquote(method)(fun, url) when is_function(fun) do
        unquote(method)(%Tesla.Client{fun: fun}, url)
      end

      if unquote(docs) do
        @spec unquote(method)(Tesla.Env.url(), [option]) :: Tesla.Env.t()
      else
        @doc false
      end

      def unquote(method)(url, options) when is_list(options) do
        request([method: unquote(method), url: url] ++ options)
      end

      if unquote(docs) do
        @doc """
        Perform a #{unquote(method |> to_string |> String.upcase())} request.
        See `request/1` or `request/2` for options definition.

        Example
            ExampleApi.#{unquote(method)}("/users")
        """
        @spec unquote(method)(Tesla.Env.url()) :: Tesla.Env.t()
      else
        @doc false
      end

      def unquote(method)(url) do
        request(method: unquote(method), url: url)
      end
    end
  end

  defmacro __before_compile__(env) do
    Tesla.Migration.breaking_alias_in_config!(env.module)

    adapter =
      env.module
      |> Module.get_attribute(:__adapter__)
      |> prepare(:adapter)

    middleware =
      env.module
      |> Module.get_attribute(:__middleware__)
      |> Enum.reverse()
      |> prepare(:middleware)

    quote do
      def __middleware__, do: unquote(middleware)
      def __adapter__, do: unquote(adapter)
    end
  end

  defmacro client(pre, post) do
    quote do
      %Tesla.Client{
        pre: unquote(prepare(pre)),
        post: unquote(prepare(post))
      }
    end
  end

  defp prepare(list, kind \\ :middleware)
  defp prepare(list, kind) when is_list(list), do: Enum.map(list, &prepare(&1, kind))
  defp prepare(nil, _), do: nil
  defp prepare({{:fn, _, _} = fun, nil, _}, _), do: {:fn, fun}

  defp prepare({{:__aliases__, _, _} = name, opts, _}, _),
    do: quote(do: {unquote(name), :call, [unquote(opts)]})

  defp prepare({name, nil, nil}, _) when is_atom(name), do: quote(do: {__MODULE__, unquote(name), []})

  defp prepare({name, nil, caller}, kind) when is_atom(name) do
    Tesla.Migration.breaking_alias!(kind, name, caller)
    quote(do: {__MODULE__, unquote(name), []})
  end
  defp prepare({name, opts}, kind), do: prepare({name, opts, nil}, kind)
  defp prepare(name, kind), do: prepare({name, nil, nil}, kind)
end
