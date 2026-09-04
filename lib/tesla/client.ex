defmodule Tesla.Client do
  @moduledoc ~S"""
  A client is the middleware stack and adapter a request runs through.

  ## Inspecting a client

  Middleware options routinely hold secrets: an `Authorization` header given
  to `Tesla.Middleware.Headers`, an API key in `Tesla.Middleware.Query`, a
  token in a custom middleware. Because `%Tesla.Env{}` embeds the client as
  `__client__`, those values would otherwise appear whenever an env or a
  client is passed to `inspect/1` — which is exactly what happens in the
  common `Logger.error("request failed: #{inspect(env)}")` pattern.

  For that reason `inspect/1` shows middleware and adapter *modules* but
  redacts their options by default:

      iex> client = Tesla.client([{Tesla.Middleware.Headers, [{"authorization", "Bearer s3cret"}]}, Tesla.Middleware.JSON])
      iex> inspect(client)
      "#Tesla.Client<adapter: nil, middleware: [{Tesla.Middleware.Headers, :redacted}, Tesla.Middleware.JSON]>"

  To see the full options while debugging, opt in:

      config :tesla, inspect: :full

  The rendering is for humans; use `Tesla.Client.middleware/1` and
  `Tesla.Client.adapter/1` to read a client's configuration from code.
  """

  @type adapter :: module | {module, any} | (Tesla.Env.t() -> Tesla.Env.result())
  @type middleware :: module | {module, any}

  @type t :: %__MODULE__{
          pre: Tesla.Env.stack(),
          post: Tesla.Env.stack(),
          adapter: Tesla.Env.runtime() | nil
        }
  defstruct fun: nil,
            pre: [],
            post: [],
            adapter: nil

  @doc ~S"""
  Returns the client's adapter in the same form it was provided.
  This can be used to copy an adapter from one client to another.

  ## Examples

      iex> client = Tesla.client([], {Tesla.Adapter.Hackney, [recv_timeout: 30_000]})
      iex> Tesla.Client.adapter(client)
      {Tesla.Adapter.Hackney, [recv_timeout: 30_000]}
  """
  @spec adapter(t) :: adapter
  def adapter(client) do
    if client.adapter, do: unruntime(client.adapter)
  end

  @doc ~S"""
  Returns the client's middleware in the same form it was provided.
  This can be used to copy middleware from one client to another.

  ## Examples

      iex> middleware = [Tesla.Middleware.JSON, {Tesla.Middleware.BaseUrl, "https://api.github.com"}]
      iex> client = Tesla.client(middleware)
      iex> Tesla.Client.middleware(client)
      [Tesla.Middleware.JSON, {Tesla.Middleware.BaseUrl, "https://api.github.com"}]
  """
  @spec middleware(t) :: [middleware]
  def middleware(client) do
    unruntime(client.pre)
  end

  @doc ~S"""
  Returns a new client with the given middleware list, preserving the rest of the original client.

  ## Examples

      iex> client = Tesla.client([Tesla.Middleware.JSON])
      iex> new_client = Tesla.Client.put_middleware(client, [Tesla.Middleware.Logger])
      iex> Tesla.Client.middleware(new_client)
      [Tesla.Middleware.Logger]
  """
  @spec put_middleware(t(), [middleware]) :: t()
  def put_middleware(client, new_middleware) when is_list(new_middleware) do
    %{client | pre: Tesla.client(new_middleware).pre}
  end

  @doc ~S"""
  Returns a new client by applying a function to the existing middleware list,
  preserving the rest of the original client.

  ## Examples

      iex> middleware = [{Tesla.Middleware.BaseUrl, "https://api.github.com"}]
      iex> client = Tesla.client(middleware)
      iex> new_client = Tesla.Client.update_middleware(client, &([Tesla.Middleware.JSON] ++ &1))
      iex> Tesla.Client.middleware(new_client)
      [Tesla.Middleware.JSON, {Tesla.Middleware.BaseUrl, "https://api.github.com"}]
  """
  @spec update_middleware(t(), ([middleware] -> [middleware])) :: t()
  def update_middleware(client, fun) do
    put_middleware(client, fun.(middleware(client)))
  end

  @doc ~S"""
  Returns a new client by applying a function to the first occurrence of the target middleware,
  preserving the rest of the original client. Raises if the target middleware is not found.

  The function receives the current middleware entry (`module` or `{module, opts}`) and must
  return the new entry. Only the first occurrence is updated if the same middleware appears
  multiple times.

  ## Examples

      iex> client = Tesla.client([{Tesla.Middleware.BaseUrl, "https://old.api.com"}])
      iex> new_client = Tesla.Client.update_middleware!(client, Tesla.Middleware.BaseUrl, fn {m, _} -> {m, "https://new.api.com"} end)
      iex> Tesla.Client.middleware(new_client)
      [{Tesla.Middleware.BaseUrl, "https://new.api.com"}]
  """
  @spec update_middleware!(t(), module, (middleware -> middleware)) :: t()
  def update_middleware!(client, target, fun) when is_atom(target) and is_function(fun, 1) do
    pre = middleware(client)
    put_middleware(client, List.update_at(pre, find_middleware_index!(pre, target), fun))
  end

  @doc ~S"""
  Returns a new client with the target middleware replaced by a new one,
  preserving the rest of the original client. Raises if the target middleware is not found.

  ## Examples

      iex> client = Tesla.client([Tesla.Middleware.JSON, Tesla.Middleware.Logger])
      iex> new_client = Tesla.Client.replace_middleware!(client, Tesla.Middleware.JSON, Tesla.Middleware.Retry)
      iex> Tesla.Client.middleware(new_client)
      [Tesla.Middleware.Retry, Tesla.Middleware.Logger]
  """
  @spec replace_middleware!(t(), module, middleware) :: t()
  def replace_middleware!(client, target, new) when is_atom(target) do
    pre = middleware(client)
    put_middleware(client, List.replace_at(pre, find_middleware_index!(pre, target), new))
  end

  @doc ~S"""
  Inserts a new middleware before or after a target middleware, preserving the rest of the original client.
  Raises if the target middleware is not found.

  ## Examples

      iex> client = Tesla.client([Tesla.Middleware.JSON])
      iex> new_client = Tesla.Client.insert_middleware!(client, Tesla.Middleware.Logger, :before, Tesla.Middleware.JSON)
      iex> Tesla.Client.middleware(new_client)
      [Tesla.Middleware.Logger, Tesla.Middleware.JSON]

      iex> client = Tesla.client([Tesla.Middleware.JSON])
      iex> new_client = Tesla.Client.insert_middleware!(client, Tesla.Middleware.Logger, :after, Tesla.Middleware.JSON)
      iex> Tesla.Client.middleware(new_client)
      [Tesla.Middleware.JSON, Tesla.Middleware.Logger]
  """
  @spec insert_middleware!(t(), middleware, :before, module) :: t()
  @spec insert_middleware!(t(), middleware, :after, module) :: t()
  def insert_middleware!(client, new, :before, target) when is_atom(target) do
    pre = middleware(client)
    put_middleware(client, List.insert_at(pre, find_middleware_index!(pre, target), new))
  end

  def insert_middleware!(client, new, :after, target) when is_atom(target) do
    pre = middleware(client)
    put_middleware(client, List.insert_at(pre, find_middleware_index!(pre, target) + 1, new))
  end

  defp find_middleware_index!(middleware, target) do
    case Enum.find_index(middleware, &matches_target?(&1, target)) do
      nil -> raise ArgumentError, "Middleware #{inspect(target)} not found"
      index -> index
    end
  end

  defp matches_target?({mw_mod, _}, target) when mw_mod == target, do: true
  defp matches_target?(target, target), do: true
  defp matches_target?(_, _), do: false

  defp unruntime(list) when is_list(list), do: Enum.map(list, &unruntime/1)
  defp unruntime({module, :call, [[]]}) when is_atom(module), do: module
  defp unruntime({module, :call, [opts]}) when is_atom(module), do: {module, opts}
  defp unruntime({:fn, fun}) when is_function(fun), do: fun

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%Tesla.Client{} = client, opts) do
      mode = Application.get_env(:tesla, :inspect, :redacted)

      fields =
        [adapter: adapter_entry(client, mode), middleware: middleware_entries(client.pre, mode)] ++
          post_entries(client.post, mode)

      container_doc("#Tesla.Client<", fields, ">", opts, &field_doc/2,
        separator: ",",
        break: :strict
      )
    end

    defp field_doc({key, value}, opts),
      do: concat([Atom.to_string(key), ": ", to_doc(value, opts)])

    defp adapter_entry(%{adapter: nil}, _mode), do: nil
    defp adapter_entry(client, :full), do: Tesla.Client.adapter(client)
    defp adapter_entry(%{adapter: adapter}, _redacted), do: redact(adapter)

    defp middleware_entries(stack, :full), do: unruntime(stack)
    defp middleware_entries(stack, _redacted), do: Enum.map(stack, &redact/1)

    defp post_entries([], _mode), do: []
    defp post_entries(stack, mode), do: [post: middleware_entries(stack, mode)]

    defp redact({module, :call, [[]]}) when is_atom(module), do: module
    defp redact({module, :call, [_opts]}) when is_atom(module), do: {module, :redacted}
    defp redact({:fn, fun}) when is_function(fun), do: :fn
    defp redact(_other), do: :redacted

    defp unruntime(stack) when is_list(stack), do: Enum.map(stack, &unruntime/1)
    defp unruntime({module, :call, [[]]}) when is_atom(module), do: module
    defp unruntime({module, :call, [opts]}) when is_atom(module), do: {module, opts}
    defp unruntime({:fn, fun}) when is_function(fun), do: fun
  end
end
