defmodule Tesla.Error do
  defexception message: "", reason: nil
end

defmodule Tesla.Env do
  @type client :: Tesla.Client.t() | (t, stack -> t)
  @type method :: :head | :get | :delete | :trace | :options | :post | :put | :patch
  @type url :: binary
  @type param :: binary | [{binary | atom, param}]
  @type query :: [{binary | atom, param}]
  @type headers :: [{binary, binary}]

  @type body :: any
  @type status :: integer
  @type opts :: [any]

  @type stack :: [{atom, atom, any} | {atom, atom} | {:fn, (t -> t)} | {:fn, (t, stack -> t)}]

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

defmodule Tesla.Client do
  @type t :: %__MODULE__{
          fun: (Tesla.Env.t(), Tesla.Env.stack() -> Tesla.Env.t()) | nil,
          pre: Tesla.Env.stack(),
          post: Tesla.Env.stack()
        }
  defstruct fun: nil,
            pre: [],
            post: []
end

defmodule Tesla.Middleware do
  @callback call(env :: Tesla.Env.t(), next :: Tesla.Env.stack(), options :: any) :: Tesla.Env.t()
end

defmodule Tesla.Adapter do
  @callback call(env :: Tesla.Env.t(), options :: any) :: Tesla.Env.t()
end

defmodule Tesla do
  use Tesla.Builder

  alias Tesla.Env

  require Tesla.Adapter.Httpc
  @default_adapter Tesla.Adapter.Httpc

  @moduledoc """
  A HTTP toolkit for building API clients using middlewares

  Include Tesla module in your api client:

  ```ex
  defmodule ExampleApi do
    use Tesla

    plug Tesla.Middleware.BaseUrl, "http://api.example.com"
    plug Tesla.Middleware.JSON
  end
  """

  defmacro __using__(opts \\ []) do
    quote do
      use Tesla.Builder, unquote(opts)
    end
  end

  @doc false
  def execute(module, %{fun: fun, pre: pre, post: post} = client, options) do
    env = struct(Env, options ++ [__module__: module, __client__: client])
    stack = pre ++ wrapfun(fun) ++ module.__middleware__ ++ post ++ [effective_adapter(module)]
    run(env, stack)
  end

  defp wrapfun(nil), do: []
  defp wrapfun(fun), do: [{:fn, fun}]

  @doc false
  def effective_adapter(module) do
    with nil <- adapter_per_module_from_config(module),
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

  # useful helper fuctions
  def put_opt(env, key, value) do
    Map.update!(env, :opts, &Keyword.put(&1, key, value))
  end

  @spec get_header(Env.t(), binary) :: binary | nil
  def get_header(%Env{headers: headers}, key) do
    case List.keyfind(headers, key, 0) do
      {_, value} -> value
      _ -> nil
    end
  end

  @spec get_headers(Env.t(), binary) :: [binary]
  def get_headers(%Env{headers: headers}, key) do
    for {k, v} <- headers, k == key, do: v
  end

  @spec put_header(Env.t(), binary, binary) :: Env.t()
  def put_header(%Env{} = env, key, value) do
    headers = List.keystore(env.headers, key, 0, {key, value})
    %{env | headers: headers}
  end

  @spec put_headers(Env.t(), [{binary, binary}]) :: Env.t()
  def put_headers(%Env{} = env, list) when is_list(list) do
    %{env | headers: env.headers ++ list}
  end

  @spec delete_header(Env.t(), binary) :: Env.t()
  def delete_header(%Env{} = env, key) do
    headers = for {k, v} <- env.headers, k != key, do: {k, v}
    %{env | headers: headers}
  end

  @spec put_body(Env.t(), Env.body()) :: Env.t()
  def put_body(%Env{} = env, body), do: %{env | body: body}

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
  defmacro build_client(pre, post \\ []) do
    quote do
      require Tesla.Builder
      Tesla.Builder.client(unquote(pre), unquote(post))
    end
  end

  def build_adapter(fun) do
    %Tesla.Client{post: [{:fn, fn env, _next -> fun.(env) end}]}
  end

  def build_url(url, []), do: url

  def build_url(url, query) do
    join = if String.contains?(url, "?"), do: "&", else: "?"
    url <> join <> encode_query(query)
  end

  defp encode_query(query) do
    query
    |> Enum.flat_map(&encode_pair/1)
    |> URI.encode_query()
  end

  defp encode_pair({key, value}) when is_list(value) do
    if Keyword.keyword?(value) do
      Enum.flat_map(value, fn {k, v} -> encode_pair({"#{key}[#{k}]", v}) end)
    else
      Enum.map(value, fn e -> {"#{key}[]", e} end)
    end
  end

  defp encode_pair({key, value}), do: [{key, value}]
end
