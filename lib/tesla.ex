defmodule Tesla.Error do
  defexception env: nil, stack: [], reason: nil

  def message(%Tesla.Error{env: %{url: url, method: method}, reason: reason}) do
    "#{inspect(reason)} (#{method |> to_string |> String.upcase()} #{url})"
  end
end

defmodule Tesla.Env do
  @moduledoc """
  This module defines a `t:Tesla.Env.t/0` struct that stores all data related to request/response.

  ## Fields

  - `:method` - method of request. Example: `:get`
  - `:url` - request url. Example: `"https://www.google.com"`
  - `:query` - list of query params.
    Example: `[{"param", "value"}]` will be translated to `?params=value`.
    Note: query params passed in url (e.g. `"/get?param=value"`) are not parsed to `query` field.
  - `:headers` - list of request/response headers.
    Example: `[{"content-type", "application/json"}]`.
    Note: request headers are overriden by response headers when adapter is called.
  - `:body` - request/response body.
    Note: request body is overriden by response body when adapter is called.
  - `:status` - response status. Example: `200`
  - `:opts` - list of options. Example: `[adapter: [recv_timeout: 30_000]]`
  """

  @type client :: Tesla.Client.t()
  @type method :: :head | :get | :delete | :trace | :options | :post | :put | :patch
  @type url :: binary
  @type param :: binary | [{binary | atom, param}]
  @type query :: [{binary | atom, param}]
  @type headers :: [{binary, binary}]

  @type body :: any
  @type status :: integer | nil
  @type opts :: keyword

  @type runtime :: {atom, atom, any} | {atom, atom} | {:fn, (t -> t)} | {:fn, (t, stack -> t)}
  @type stack :: [runtime]
  @type result :: {:ok, t()} | {:error, any}

  @type t :: %__MODULE__{
          method: method,
          query: query,
          url: url,
          headers: headers,
          body: body,
          status: status,
          opts: opts,
          __module__: atom,
          __client__: client
        }

  defstruct method: nil,
            url: "",
            query: [],
            headers: [],
            body: nil,
            status: nil,
            opts: [],
            __module__: nil,
            __client__: nil
end

defmodule Tesla.Middleware do
  @moduledoc """
  The middleware specification.

  Middleware is an extension of basic `Tesla` functionality. It is a module that must
  implement `c:Tesla.Middleware.call/3`.

  ## Middleware options

  Options can be passed to middleware in second param of `Tesla.Builder.plug/2` macro:

      plug Tesla.Middleware.BaseUrl, "https://example.com"

  or inside tuple in case of dynamic middleware (`Tesla.client/1`):

      Tesla.client([{Tesla.Middleware.BaseUrl, "https://example.com"}])

  ## Writing custom middleware

  Writing custom middleware is as simple as creating a module implementing `c:Tesla.Middleware.call/3`.

  See `c:Tesla.Middleware.call/3` for details.

  ### Examples

      defmodule MyProject.InspectHeadersMiddleware do
        @behaviour Tesla.Middleware

        @impl Tesla.Middleware
        def call(env, next, options) do
          env
          |> inspect_headers(options)
          |> Tesla.run(next)
          |> inspect_headers(options)
        end

        defp inspect_headers(env, options) do
          IO.inspect(env.headers, options)
        end
      end

  """

  @doc """
  Invoked when a request runs.

  - (optionally) read and/or writes request data
  - calls `Tesla.run/2`
  - (optionally) read and/or writes response data

  ## Arguments

  - `env` - `Tesla.Env` struct that stores request/response data
  - `next` - middlewares that should be called after current one
  - `options` - middleware options provided by user
  """
  @callback call(env :: Tesla.Env.t(), next :: Tesla.Env.stack(), options :: any) ::
              Tesla.Env.result()
end

defmodule Tesla.Adapter do
  @moduledoc """
  The adapter specification.

  Adapter is a module that denormalize request data stored in `Tesla.Env` in order to make
  request with lower level http client (e.g. `:httpc` or `:hackney`) and normalize response data
  in order to store it back to `Tesla.Env`. It has to implement `c:Tesla.Adapter.call/2`.

  ## Writing custom adapter

  Create a module implementing `c:Tesla.Adapter.call/2`.

  See `c:Tesla.Adapter.call/2` for details.

  ### Examples

      defmodule MyProject.CustomAdapter do
        alias Tesla.Multipart

        @behaviour Tesla.Adapter

        @override_defaults [follow_redirect: false]

        @impl Tesla.Adapter
        def call(env, opts) do
          opts = Tesla.Adapter.opts(@override_defaults, env, opts)

          with {:ok, {status, headers, body}} <- request(env.method, env.body, env.headers, opts) do
            {:ok, normalize_response(env, status, headers, body)}
          end
        end

        defp request(_method, %Stream{}, _headers, _opts) do
          {:error, "stream not supported by adapter"}
        end

        defp request(_method, %Multipart{}, _headers, _opts) do
          {:error, "multipart not supported by adapter"}
        end

        defp request(method, body, headers, opts) do
          :lower_level_http.request(method, body, denormalize_headers(headers), opts)
        end

        defp denormalize_headers(headers), do: ...
        defp normalize_response(env, status, headers, body), do: %Tesla.Env{env | ...}
      end

  """

  @doc """
  Invoked when a request runs.

  ## Arguments

  - `env` - `Tesla.Env` struct that stores request/response data
  - `options` - middleware options provided by user
  """
  @callback call(env :: Tesla.Env.t(), options :: any) :: Tesla.Env.result()

  @doc """
  Helper function that merges all adapter options.

  ## Arguments

  - `defaults` (optional) - useful to override lower level http client default configuration
  - `env` - `Tesla.Env` struct
  - `opts` - options provided to `Tesla.Builder.adapter/2` macro

  ## Precedence rules

  - config from `opts` overrides config from `defaults` when same key is encountered
  - config from `env` overrides config from both `defaults` and `opts` when same key is encountered
  """
  @spec opts(Keyword.t(), Tesla.Env.t(), Keyword.t()) :: Keyword.t()
  def opts(defaults \\ [], env, opts) do
    defaults
    |> Keyword.merge(opts || [])
    |> Keyword.merge(env.opts[:adapter] || [])
  end
end

defmodule Tesla do
  use Tesla.Builder

  alias Tesla.Env

  require Tesla.Adapter.Httpc
  @default_adapter Tesla.Adapter.Httpc

  @moduledoc """
  A HTTP toolkit for building API clients using middlewares.

  ## Building API client

  `use Tesla` macro will generate basic HTTP functions (e.g. `get/3`, `post/4`, etc.) inside your module.

  It supports following options:

  - `:only` - builder will generate only functions included in the given list
  - `:except` - builder will not generate the functions that are listed in the options
  - `:docs` - when set to false builder will not add documentation to generated functions

  ### Examples

      defmodule ExampleApi do
        use Tesla, only: [:get], docs: false

        plug Tesla.Middleware.BaseUrl, "http://api.example.com"
        plug Tesla.Middleware.JSON

        def fetch_data do
          get("/data")
        end
      end

  In example above `ExampleApi.fetch_data/0` is equivalent of `ExampleApi.get("/data")`.

      defmodule ExampleApi do
        use Tesla, except: [:post, :delete]

        plug Tesla.Middleware.BaseUrl, "http://api.example.com"
        plug Tesla.Middleware.JSON

        def fetch_data do
          get("/data")
        end
      end

  In example above `except: [:post, :delete]` will make sure that post functions will not be generated for this module.

  ## Direct usage

  It is also possible to do request directly with `Tesla` module.

      Tesla.get("https://example.com")

  ### Common pitfalls

  Direct usage won't include any middlewares.

  In following example:

      defmodule ExampleApi do
        use Tesla, only: [:get], docs: false

        plug Tesla.Middleware.BaseUrl, "http://api.example.com"
        plug Tesla.Middleware.JSON

        def fetch_data do
          Tesla.get("/data")
        end
      end

  call to `ExampleApi.fetch_data/0` will fail, because request will be missing base URL.

  ## Default adapter

  By default `Tesla` is using `Tesla.Adapter.Httpc`, because `:httpc` is included in Erlang/OTP and
  does not require installation of any additional dependency. It can be changed globally with config:

      config :tesla, :adapter, Tesla.Adapter.Hackney

  or by `Tesla.Builder.adapter/2` macro for given API client module:

      defmodule ExampleApi do
        use Tesla

        adapter Tesla.Adapter.Hackney

        ...
      end

  """

  defmacro __using__(opts \\ []) do
    quote do
      use Tesla.Builder, unquote(opts)
    end
  end

  @doc false
  def execute(module, client, options) do
    {env, stack} = prepare(module, client, options)
    run(env, stack)
  end

  @doc false
  def execute!(module, client, options) do
    {env, stack} = prepare(module, client, options)

    case run(env, stack) do
      {:ok, env} -> env
      {:error, error} -> raise Tesla.Error, env: env, stack: stack, reason: error
    end
  end

  defp prepare(module, %{pre: pre, post: post} = client, options) do
    env = struct(Env, options ++ [__module__: module, __client__: client])
    stack = pre ++ module.__middleware__ ++ post ++ [effective_adapter(module, client)]
    {env, stack}
  end

  @doc false
  def effective_adapter(module, client \\ %Tesla.Client{}) do
    with nil <- client.adapter,
         nil <- adapter_per_module_from_config(module),
         nil <- adapter_per_module(module),
         nil <- adapter_from_config() do
      adapter_default()
    end
  end

  defp adapter_per_module_from_config(module) do
    case Application.get_env(:tesla, module, [])[:adapter] do
      nil -> nil
      {adapter, opts} -> {adapter, :call, [opts]}
      adapter -> {adapter, :call, [[]]}
    end
  end

  defp adapter_per_module(module) do
    module.__adapter__
  end

  defp adapter_from_config do
    case Application.get_env(:tesla, :adapter) do
      nil -> nil
      {adapter, opts} -> {adapter, :call, [opts]}
      adapter -> {adapter, :call, [[]]}
    end
  end

  defp adapter_default do
    {@default_adapter, :call, [[]]}
  end

  def run_default_adapter(env, opts \\ []) do
    apply(@default_adapter, :call, [env, opts])
  end

  # empty stack case is useful for reusing/testing middlewares (just pass [] as next)
  def run(env, []), do: {:ok, env}

  # last item in stack is adapter - skip passing rest of stack
  def run(env, [{:fn, f}]), do: apply(f, [env])
  def run(env, [{m, f, a}]), do: apply(m, f, [env | a])

  # for all other elements pass (env, next, opts)
  def run(env, [{:fn, f} | rest]), do: apply(f, [env, rest])
  def run(env, [{m, f, a} | rest]), do: apply(m, f, [env, rest | a])

  @doc """
  Adds given key/value pair to `:opts` field in `Tesla.Env`.

  Useful when there's need to store additional middleware data in `Tesla.Env`

  ## Examples

      iex> %Tesla.Env{opts: []} |> Tesla.put_opt(:option, "value")
      %Tesla.Env{opts: [option: "value"]}

  """
  @spec put_opt(Tesla.Env.t(), atom, any) :: Tesla.Env.t()
  def put_opt(env, key, value) do
    Map.update!(env, :opts, &Keyword.put(&1, key, value))
  end

  @doc """
  Returns value of header specified by `key` from `:headers` field in `Tesla.Env`.

  ## Examples

      # non existing header
      iex> env = %Tesla.Env{headers: [{"server", "Cowboy"}]}
      iex> Tesla.get_header(env, "some-key")
      nil

      # existing header
      iex> env = %Tesla.Env{headers: [{"server", "Cowboy"}]}
      iex> Tesla.get_header(env, "server")
      "Cowboy"

      # first of multiple headers with the same name
      iex> env = %Tesla.Env{headers: [{"cookie", "chocolate"}, {"cookie", "biscuits"}]}
      iex> Tesla.get_header(env, "cookie")
      "chocolate"

  """
  @spec get_header(Env.t(), binary) :: binary | nil
  def get_header(%Env{headers: headers}, key) do
    case List.keyfind(headers, key, 0) do
      {_, value} -> value
      _ -> nil
    end
  end

  @spec get_headers(Env.t(), binary) :: [binary]
  def get_headers(%Env{headers: headers}, key) when is_binary(key) do
    for {k, v} <- headers, k == key, do: v
  end

  @spec put_header(Env.t(), binary, binary) :: Env.t()
  def put_header(%Env{} = env, key, value) when is_binary(key) and is_binary(value) do
    headers = List.keystore(env.headers, key, 0, {key, value})
    %{env | headers: headers}
  end

  @spec put_headers(Env.t(), [{binary, binary}]) :: Env.t()
  def put_headers(%Env{} = env, list) when is_list(list) do
    %{env | headers: env.headers ++ list}
  end

  @spec delete_header(Env.t(), binary) :: Env.t()
  def delete_header(%Env{} = env, key) when is_binary(key) do
    headers = for {k, v} <- env.headers, k != key, do: {k, v}
    %{env | headers: headers}
  end

  @spec put_body(Env.t(), Env.body()) :: Env.t()
  def put_body(%Env{} = env, body), do: %{env | body: body}

  @doc """
  Dynamically build client from list of middlewares and/or adapter.

  ```
  # add dynamic middleware
  client = Tesla.client([{Tesla.Middleware.Headers, [{"authorization", token}]}])
  Tesla.get(client, "/path")

  # configure adapter in runtime
  client = Tesla.client([], Tesla.Adapter.Hackney)
  client = Tesla.client([], {Tesla.Adapter.Hackney, pool: :my_pool})
  Tesla.get(client, "/path")

  # complete module example
  defmodule MyApi do
    # note there is no need for `use Tesla`

    @middleware [
      {Tesla.Middleware.BaseUrl, "https://example.com"},
      Tesla.Middleware.JSON,
      Tesla.Middleware.Logger
    ]

    @adapter Tesla.Adapter.Hackney

    def new(opts) do
      # do any middleware manipulation you need
      middleware = [
        {Tesla.Middleware.BasicAuth, username: opts[:username], password: opts[:password]}
      ] ++ @middleware

      # allow configuring adapter in runtime
      adapter = opts[:adapter] || @adapter

      # use Tesla.client/2 to put it all together
      Tesla.client(middleware, adapter)
    end

    def get_something(client, id) do
      # pass client directly to Tesla.get/2
      Tesla.get(client, "/something/\#{id}")
      # ...
    end
  end

  client = MyApi.new(username: "admin", password: "secret")
  MyApi.get_something(client, 42)
  ```
  """
  if Version.match?(System.version(), "~> 1.7"), do: @doc(since: "1.2.0")
  @spec client([Tesla.Client.middleware()], Tesla.Client.adapter()) :: Tesla.Client.t()
  def client(middleware, adapter \\ nil), do: Tesla.Builder.client(middleware, [], adapter)

  @deprecated "Use client/1 or client/2 instead"
  def build_client(pre, post \\ []), do: Tesla.Builder.client(pre, post)

  @deprecated "Use client/1 or client/2 instead"
  def build_adapter(fun), do: Tesla.Builder.client([], [], fun)

  @doc """
  Builds URL with the given query params.

  Useful when you need to create an URL with dynamic query params from a Keyword list

  ## Examples

      iex> Tesla.build_url("http://api.example.com", [user: 3, page: 2])
      "http://api.example.com?user=3&page=2"

      # URL that already contains query params
      iex> url = "http://api.example.com?user=3"
      iex> Tesla.build_url(url, [page: 2, status: true])
      "http://api.example.com?user=3&page=2&status=true"

  """
  @spec build_url(Tesla.Env.url(), Tesla.Env.query()) :: binary
  def build_url(url, []), do: url

  def build_url(url, query) do
    join = if String.contains?(url, "?"), do: "&", else: "?"
    url <> join <> encode_query(query)
  end

  def encode_query(query) do
    query
    |> Enum.flat_map(&encode_pair/1)
    |> URI.encode_query()
  end

  @doc false
  def encode_pair({key, value}) when is_list(value) do
    if Keyword.keyword?(value) do
      Enum.flat_map(value, fn {k, v} -> encode_pair({"#{key}[#{k}]", v}) end)
    else
      Enum.map(value, fn e -> {"#{key}[]", e} end)
    end
  end

  @doc false
  def encode_pair({key, value}), do: [{key, value}]
end
