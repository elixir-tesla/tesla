defmodule Tesla.Error do
  defexception message: "", reason: nil
end

defmodule Tesla.Env do
  @type client :: Tesla.Client.t() | (t, stack -> t)
  @type method :: :head | :get | :delete | :trace | :options | :post | :put | :patch
  @type url :: binary
  @type param :: binary | [{binary | atom, param}]
  @type query :: [{binary | atom, param}]
  @type headers :: %{binary => binary}
  #
  @type body :: any
  @type status :: integer
  @type opts :: [any]
  @type __module__ :: atom
  @type __client__ :: function

  @type stack :: [{atom, atom, any} | {atom, atom} | {:fn, (t -> t)} | {:fn, (t, stack -> t)}]

  @type t :: %__MODULE__{
          method: method,
          query: query,
          url: url,
          headers: headers,
          body: body,
          status: status,
          opts: opts,
          __module__: __module__,
          __client__: __client__
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

  def perform_request(module, client \\ nil, options) do
    %{fun: fun, pre: pre, post: post} = client || %Tesla.Client{}

    stack = pre ++ wrapfun(fun) ++ module.__middleware__ ++ post ++ [module.__adapter__]

    env = struct(Tesla.Env, options ++ [__module__: module, __client__: client])
    run(env, stack)
  end

  defp wrapfun(nil), do: []
  defp wrapfun(fun), do: [{:fn, fun}]

  # empty stack case is useful for reusing/testing middlewares (just pass [] as next)
  def run(env, []), do: env

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

  @spec get_header(Tesla.Env.t, binary) :: binary | nil
  def get_header(%Tesla.Env{headers: headers}, key) when is_list(headers) do
    case List.keyfind(headers, key, 0) do
      {_, value} -> value
      _ -> nil
    end
  end

  @spec get_headers(Tesla.Env.t, binary) :: [binary]
  def get_headers(%Tesla.Env{headers: headers}, key) do
    for {k,v} <- headers, k == key, do: v
  end

  @spec put_header(Tesla.Env.t, binary, binary) :: Tesla.Env.t
  def put_header(env, key, value) do
    headers = List.keystore(env.headers, key, 0, {key, value})
    %{env | headers: headers}
  end

  @spec put_headers(Tesla.Env.t, [{binary, binary}]) :: Tesla.Env.t
  def put_headers(env, list) when is_list(list) do
    %{env | headers: env.headers ++ list}
  end

  @spec delete_header(Tesla.Env.t, binary) :: Tesla.Env.t
  def delete_header(env, key) do
    headers = for {k,v} <- env.headers, k != key, do: {k,v}
    %{env | headers: headers}
  end

  def adapter(module, custom) do
    cond do
      mod = module_adapter_from_config(module) -> {mod, :call, [[]]}
      custom -> custom
      true -> {default_adapter(), :call, [[]]}
    end
  end

  defp module_adapter_from_config(module) do
    Application.get_env(:tesla, module, [])[:adapter]
  end

  def default_adapter do
    Application.get_env(:tesla, :adapter, Tesla.Adapter.Httpc)
  end

  def run_default_adapter(env, opts \\ []) do
    apply(default_adapter(), :call, [env, opts])
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
