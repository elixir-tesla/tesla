defmodule Tesla.Env do
  @type client      :: (t,stack -> t)
  @type method      :: :head | :get | :delete | :trace | :options | :post | :put | :patch
  @type url         :: binary
  @type param       :: binary | %{binary => param} | [param]
  @type query       :: %{binary => param}
  @type headers     :: [{binary, binary}]
  @type body        :: any #
  @type status      :: integer
  @type opts        :: [any]

  @type stack       :: [{atom, atom, any}]

  @type t :: %__MODULE__{
    method:   method,
    query:    query,
    url:      url,
    headers:  headers,
    body:     body,
    status:   status
  }

  defstruct method:   nil,
            url:      "",
            query:    [],
            headers:  [],
            body:     nil,
            status:   nil
end

defmodule Tesla do
  @moduledoc """
  A HTTP toolkit for buuiling middlewares
  """


  @doc """
  Include Tesla module in your api client:

  ```ex
  defmodule ExampleApi do
    use Tesla

    plug Tesla.Middleware.BaseURL, "http://api.example.com"
    plug Tesla.Middleware.JSON
  end
  """
  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :__middleware__, accumulate: true)
      Module.register_attribute(__MODULE__, :__adapter__, [])

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
      def request(client, options) do
        Tesla.request(__MODULE__, client, options)
      end

      @doc """
      Perform a request. See `request/2` for available options.
      """
      @spec request([option]) :: Tesla.Env.t
      def request(options) do
        Tesla.request(__MODULE__, options)
      end

      unquote(generate_api(:head))
      unquote(generate_api(:get))
      unquote(generate_api(:delete))
      unquote(generate_api(:trace))
      unquote(generate_api(:options))
      unquote(generate_api(:post))
      unquote(generate_api(:put))
      unquote(generate_api(:patch))

      import Tesla, only: [plug: 1, plug: 2, adapter: 1, adapter: 2]
      @before_compile Tesla
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
  @spec plug(Atom, any) :: nil
  defmacro plug(middleware, opts \\ nil) do
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
  @spec adapter(Function, any) :: nil
  defmacro adapter({:fn, _, _} = adapter) do
    adapter = Macro.escape(adapter)
    quote do: @__adapter__ unquote(adapter)
  end

  @spec adapter(Atom, any) :: nil
  defmacro adapter(adapter, opts \\ nil) do
    quote do: @__adapter__ {unquote(adapter), unquote(opts)}
  end

  defp generate_api(method) when method in [:post, :put, :patch] do
    quote do
      @doc """
      Perform a #{unquote(method |> to_string |> String.upcase)} request.
      See `request/1` or `request/2` for options definition.

      Example
          iex> myclient |> ExampleApi.#{unquote(method)}("/users", %{name: "Jon"}, query: [scope: "admin"])
      """
      @spec unquote(method)(Tesla.Env.client, Tesla.Env.url, Tesla.Env.body, [option]) :: Tesla.Env.t
      def unquote(method)(client, url, body, options) when is_function(client) do
        request(client, [method: unquote(method), url: url, body: body] ++ options)
      end

      @doc """
      Perform a #{unquote(method |> to_string |> String.upcase)} request.
      See `request/1` or `request/2` for options definition.

      Example
          iex> myclient |> ExampleApi.#{unquote(method)}("/users", %{name: "Jon"})
          iex> ExampleApi.#{unquote(method)}("/users", %{name: "Jon"}, query: [scope: "admin"])
      """
      @spec unquote(method)(Tesla.Env.client, Tesla.Env.url, Tesla.Env.body) :: Tesla.Env.t
      def unquote(method)(client, url, body) when is_function(client) do
        request(client, method: unquote(method), url: url, body: body)
      end
      @spec unquote(method)(Tesla.Env.url, Tesla.Env.body, [option]) :: Tesla.Env.t
      def unquote(method)(url, body, options) do
        request([method: unquote(method), url: url, body: body] ++ options)
      end

      @doc """
      Perform a #{unquote(method |> to_string |> String.upcase)} request.
      See `request/1` or `request/2` for options definition.

      Example
          iex> ExampleApi.#{unquote(method)}("/users", %{name: "Jon"})
      """
      @spec unquote(method)(Tesla.Env.url, Tesla.Env.body) :: Tesla.Env.t
      def unquote(method)(url, body) do
        request(method: unquote(method), url: url, body: body)
      end
    end
  end

  defp generate_api(method) when method in [:head, :get, :delete, :trace, :options] do
    quote do
      @doc """
      Perform a #{unquote(method |> to_string |> String.upcase)} request.
      See `request/1` or `request/2` for options definition.

      Example
          iex> myclient |> ExampleApi.#{unquote(method)}("/users", query: [page: 1])
      """
      @spec unquote(method)(Tesla.Env.client, Tesla.Env.url, [option]) :: Tesla.Env.t
      def unquote(method)(client, url, options) when is_function(client) do
        request(client, [method: unquote(method), url: url] ++ options)
      end

      @doc """
      Perform a #{unquote(method |> to_string |> String.upcase)} request.
      See `request/1` or `request/2` for options definition.

      Example
          iex> myclient |> ExampleApi.#{unquote(method)}("/users")
          iex> ExampleApi.#{unquote(method)}("/users", query: [page: 1])
      """
      @spec unquote(method)(Tesla.Env.client, Tesla.Env.url) :: Tesla.Env.t
      def unquote(method)(client, url) when is_function(client) do
        request(client, method: unquote(method), url: url)
      end
      @spec unquote(method)(Tesla.Env.url, [option]) :: Tesla.Env.t
      def unquote(method)(url, options) do
        request([method: unquote(method), url: url] ++ options)
      end

      @doc """
      Perform a #{unquote(method |> to_string |> String.upcase)} request.
      See `request/1` or `request/2` for options definition.

      Example
          iex> ExampleApi.#{unquote(method)}("/users")
      """
      @spec unquote(method)(Tesla.Env.url) :: Tesla.Env.t
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


  def request(module, client, options), do: do_request(module, [client], options)
  def request(module, options), do: do_request(module, [], options)

  defp do_request(module, clients, options) do
    stack = prepare(module, clients ++ module.__middleware__ ++ [module.__adapter__])
    env   = struct(Tesla.Env, options)
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

  # last item in stack is adapter - skip passing rest of stack
  def run(env, [{:fn, f}]),  do: apply(f, [env])
  def run(env, [{m,f}]),     do: apply(m, f, [env])
  def run(env, [{m,f,a}]),   do: apply(m, f, [env | a])

  # for all other elements pass (env, next, opts)
  def run(env, [{:fn, f} | rest]),  do: apply(f, [env, rest])
  def run(env, [{m,f} | rest]),     do: apply(m, f, [env, rest])
  def run(env, [{m,f,a} | rest]),   do: apply(m, f, [env, rest | a])

  def default_adapter do
    adapter = Application.get_env(:tesla, :adapter, Tesla.Adapters.Httpc)
    {adapter, []}
  end

  @spec build_client([{Atom, any}]) :: Tesla.Env.client
  defmacro build_client(stack) do
    quote do
      fn env,next -> Tesla.run(env, Tesla.prepare(__MODULE__, unquote(stack)) ++ next) end
    end
  end
end

defmodule Tesla.Client do
  use Tesla
end
