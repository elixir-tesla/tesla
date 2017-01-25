defmodule Tesla.Error do
  defexception message: "", reason: nil
end

defmodule Tesla.Env do
  @type client      :: (t,stack -> t)
  @type method      :: :head | :get | :delete | :trace | :options | :post | :put | :patch
  @type url         :: binary
  @type param       :: binary | [{(binary | atom), param}]
  @type query       :: [{(binary | atom), param}]
  @type headers     :: %{binary => binary}
  @type body        :: any #
  @type status      :: integer
  @type opts        :: [any]
  @type __module__  :: atom
  @type __client__  :: function

  @type stack       :: [{atom, atom, any}]

  @type t :: %__MODULE__{
            method:     method,
            query:      query,
            url:        url,
            headers:    headers,
            body:       body,
            status:     status,
            opts:       opts,
            __module__: __module__,
            __client__: __client__
  }

  defstruct method:     nil,
            url:        "",
            query:      [],
            headers:    %{},
            body:       nil,
            status:     nil,
            opts:       [],
            __module__: nil,
            __client__: nil
end

defmodule Tesla.Builder do
  @http_verbs ~w(head get delete trace options post put patch)a

  defmacro __using__(opts \\ []) do
    opts = Macro.prewalk(opts, &Macro.expand(&1, __CALLER__))
    docs = Keyword.get(opts, :docs, true)

    quote do
      Module.register_attribute(__MODULE__, :__middleware__, accumulate: true)
      Module.register_attribute(__MODULE__, :__adapter__, [])

      if unquote(docs) do
        @type option :: {:method,   Tesla.Env.method}  |
                        {:url,      Tesla.Env.url}     |
                        {:query,    Tesla.Env.query}   |
                        {:headers,  Tesla.Env.headers} |
                        {:body,     Tesla.Env.body}    |
                        {:opts,     Tesla.Env.opts}

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

            iex> ExampleApi.request(method: :get, url: "/users/path")

        You can also use shortcut methods like:

            iex> ExampleApi.get("/users/1")

        or

            iex> myclient |> ExampleApi.post("/users", %{name: "Jon"})
        """
        @spec request(Tesla.Env.client, [option]) :: Tesla.Env.t
      else
        @doc false
      end
      def request(client, options) do
        Tesla.perform_request(__MODULE__, client, options)
      end

      if unquote(docs) do
        @doc """
        Perform a request. See `request/2` for available options.
        """
        @spec request([option]) :: Tesla.Env.t
      else
        @doc false
      end
      def request(options) do
        Tesla.perform_request(__MODULE__, options)
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
    plug Tesla.Middleware.BaseURL, "http://api.example.com"
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
    opts = Macro.escape(opts)
    middleware = Tesla.alias(middleware)
    quote do: @__middleware__ {unquote(middleware), unquote(opts)}
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
  defmacro adapter({:fn, _, _} = adapter) do
    adapter = Macro.escape(adapter)
    quote do: @__adapter__ unquote(adapter)
  end
  defmacro adapter(adapter, opts \\ nil) do
    adapter = Tesla.alias(adapter)
    quote do: @__adapter__ {unquote(adapter), unquote(opts)}
  end

  defp generate_http_verbs(opts) do
    only    = Keyword.get(opts, :only,    @http_verbs)
    except  = Keyword.get(opts, :except,  [])

    @http_verbs
    |> Enum.filter(&(&1 in only && not &1 in except))
    |> Enum.map(&generate_api(&1, Keyword.get(opts, :docs, true)))
  end

  defp generate_api(method, docs) when method in [:post, :put, :patch] do
    quote do
      if unquote(docs) do
        @doc """
        Perform a #{unquote(method |> to_string |> String.upcase)} request.
        See `request/1` or `request/2` for options definition.

        Example
            iex> myclient |> ExampleApi.#{unquote(method)}("/users", %{name: "Jon"}, query: [scope: "admin"])
        """
        @spec unquote(method)(Tesla.Env.client, Tesla.Env.url, Tesla.Env.body, [option]) :: Tesla.Env.t
      else
        @doc false
      end
      def unquote(method)(client, url, body, options) when is_function(client) do
        request(client, [method: unquote(method), url: url, body: body] ++ options)
      end

      if unquote(docs) do
        @doc """
        Perform a #{unquote(method |> to_string |> String.upcase)} request.
        See `request/1` or `request/2` for options definition.

        Example
            iex> myclient |> ExampleApi.#{unquote(method)}("/users", %{name: "Jon"})
            iex> ExampleApi.#{unquote(method)}("/users", %{name: "Jon"}, query: [scope: "admin"])
        """
        @spec unquote(method)(Tesla.Env.client, Tesla.Env.url, Tesla.Env.body) :: Tesla.Env.t
      else
        @doc false
      end
      def unquote(method)(client, url, body) when is_function(client) do
        request(client, method: unquote(method), url: url, body: body)
      end
      if unquote(docs) do
        @spec unquote(method)(Tesla.Env.url, Tesla.Env.body, [option]) :: Tesla.Env.t
      else
        @doc false
      end
      def unquote(method)(url, body, options) do
        request([method: unquote(method), url: url, body: body] ++ options)
      end

      if unquote(docs) do
        @doc """
        Perform a #{unquote(method |> to_string |> String.upcase)} request.
        See `request/1` or `request/2` for options definition.

        Example
            iex> ExampleApi.#{unquote(method)}("/users", %{name: "Jon"})
        """
        @spec unquote(method)(Tesla.Env.url, Tesla.Env.body) :: Tesla.Env.t
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
        Perform a #{unquote(method |> to_string |> String.upcase)} request.
        See `request/1` or `request/2` for options definition.

        Example
            iex> myclient |> ExampleApi.#{unquote(method)}("/users", query: [page: 1])
        """
        @spec unquote(method)(Tesla.Env.client, Tesla.Env.url, [option]) :: Tesla.Env.t
      else
        @doc false
      end
      def unquote(method)(client, url, options) when is_function(client) do
        request(client, [method: unquote(method), url: url] ++ options)
      end

      if unquote(docs) do
        @doc """
        Perform a #{unquote(method |> to_string |> String.upcase)} request.
        See `request/1` or `request/2` for options definition.

        Example
            iex> myclient |> ExampleApi.#{unquote(method)}("/users")
            iex> ExampleApi.#{unquote(method)}("/users", query: [page: 1])
        """
        @spec unquote(method)(Tesla.Env.client, Tesla.Env.url) :: Tesla.Env.t
      else
        @doc false
      end
      def unquote(method)(client, url) when is_function(client) do
        request(client, method: unquote(method), url: url)
      end
      if unquote(docs) do
        @spec unquote(method)(Tesla.Env.url, [option]) :: Tesla.Env.t
      else
        @doc false
      end
      def unquote(method)(url, options) do
        request([method: unquote(method), url: url] ++ options)
      end

      if unquote(docs) do
        @doc """
        Perform a #{unquote(method |> to_string |> String.upcase)} request.
        See `request/1` or `request/2` for options definition.

        Example
            iex> ExampleApi.#{unquote(method)}("/users")
        """
        @spec unquote(method)(Tesla.Env.url) :: Tesla.Env.t
      else
        @doc false
      end
      def unquote(method)(url) do
        request(method: unquote(method), url: url)
      end
    end
  end

  defmacro __before_compile__(env) do
    adapter     = Module.get_attribute(env.module, :__adapter__) || quote(do: Tesla.default_adapter)
    middleware  = Module.get_attribute(env.module, :__middleware__) |> Enum.reverse

    quote do
      def __middleware__, do: unquote(middleware)
      def __adapter__, do: unquote(adapter)
    end
  end
end

defmodule Tesla do
  use Tesla.Builder

  @moduledoc """
  A HTTP toolkit for building API clients using middlewares

  Include Tesla module in your api client:

  ```ex
  defmodule ExampleApi do
    use Tesla

    plug Tesla.Middleware.BaseURL, "http://api.example.com"
    plug Tesla.Middleware.JSON
  end
  """

  defmacro __using__(opts \\ []) do
    quote do
      use Tesla.Builder, unquote(opts)
    end
  end

  @aliases [
    httpc:    Tesla.Adapter.Httpc,
    hackney:  Tesla.Adapter.Hackney,
    ibrowse:  Tesla.Adapter.Ibrowse,

    base_url:     Tesla.Middleware.BaseUrl,
    headers:      Tesla.Middleware.Headers,
    query:        Tesla.Middleware.Query,
    decode_rels:  Tesla.Middleware.DecodeRels,
    json:         Tesla.Middleware.JSON,
    logger:       Tesla.Middleware.Logger,
    debug_logger: Tesla.Middleware.DebugLogger
  ]
  def alias(key) when is_atom(key), do: Keyword.get(@aliases, key, key)
  def alias(key), do: key

  def perform_request(module, client \\ nil, options) do
    stack = prepare(module, List.wrap(client) ++ module.__middleware__ ++ default_middleware() ++ [module.__adapter__])
    env   = struct(Tesla.Env, options ++ [__module__: module, __client__: client])
    run(env, stack)
  end

  def prepare(module, stack) do
    Enum.map stack, fn
      {name, opts}              -> prepare_module(module, name, opts)
      name when is_atom(name)   -> prepare_module(module, name, nil)
      fun when is_function(fun) -> {:fn, fun}
    end
  end

  defp prepare_module(module, name, opts) do
    case Atom.to_char_list(name) do
      ~c"Elixir." ++ _ -> {name,   :call, [opts]}
      _                -> {module, name}
    end
  end

  # empty stack case is useful for reusing/testing middlewares (just pass [] as next)
  def run(env, []), do: env

  # last item in stack is adapter - skip passing rest of stack
  def run(env, [{:fn, f}]),  do: apply(f, [env])
  def run(env, [{m,f}]),     do: apply(m, f, [env])
  def run(env, [{m,f,a}]),   do: apply(m, f, [env | a])

  # for all other elements pass (env, next, opts)
  def run(env, [{:fn, f} | rest]),  do: apply(f, [env, rest])
  def run(env, [{m,f} | rest]),     do: apply(m, f, [env, rest])
  def run(env, [{m,f,a} | rest]),   do: apply(m, f, [env, rest | a])

  # useful helper fuctions
  def put_opt(env, key, value) do
    Map.update!(env, :opts, &Keyword.put(&1, key, value))
  end


  def default_adapter do
    adapter = Application.get_env(:tesla, :adapter, :httpc) |> Tesla.alias
    {adapter, []}
  end

  def default_middleware do
    [{Tesla.Middleware.Normalize, nil}]
  end


  @doc """
  Dynamically build client from list of middlewares.

  ```ex
  defmodule ExampleAPI do
    use Tesla

    def new(token) do
      Tesla.build_client([
        {Tesla.Middleware.Headers, %{"Authorization" => token}}
      ])
    end
  end

  client = ExampleAPI.new(token: "abc")
  client |> ExampleAPI.get("/me")
  ```
  """
  defmacro build_client(stack) do
    quote do
      fn env, next -> Tesla.run(env, Tesla.prepare(__MODULE__, unquote(stack)) ++ next) end
    end
  end

  def build_url(url, []), do: url
  def build_url(url, query) do
    join = if String.contains?(url, "?"), do: "&", else: "?"
    url <> join <> encode_query(query)
  end

  defp encode_query(query) do
    query
    |> Enum.flat_map(&encode_pair/1)
    |> URI.encode_query
  end

  defp encode_pair({key, value}) when is_list(value) do
    if Keyword.keyword?(value) do
      Enum.flat_map(value, fn {k,v} -> encode_pair({"#{key}[#{k}]", v}) end)
    else
      Enum.map(value, fn e -> {"#{key}[]", e} end)
    end
  end
  defp encode_pair({key, value}), do: [{key, value}]
end
