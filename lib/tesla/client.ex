defmodule Tesla.Client do
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
    unruntime(client.adapter)
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

  defp unruntime(list) when is_list(list), do: Enum.map(list, &unruntime/1)
  defp unruntime({module, :call, [[]]}) when is_atom(module), do: module
  defp unruntime({module, :call, [opts]}) when is_atom(module), do: {module, opts}
  defp unruntime({:fn, fun}) when is_function(fun), do: fun

  def insert(client, new, before: target) when is_atom(target) do
    insert_at(client, new, target, 0)
  end

  def insert(client, new, after: target) when is_atom(target) do
    insert_at(client, new, target, 1)
  end

  def insert_at(client, new, target, adjust) do
    pre = middleware(client)

    index =
      Enum.find_index(client.pre, fn
        {^target, :call, _} -> true
        _ -> false
      end)

    if index == nil, do: raise("Middleware #{inspect(target)} not found in #{inspect(client)}")

    pre = List.insert_at(pre, index + adjust, new)
    Tesla.Builder.client(pre, unruntime(client.post), adapter(client))
  end
end
