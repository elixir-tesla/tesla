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

  defp unruntime(list) when is_list(list), do: Enum.map(list, &unruntime/1)
  defp unruntime({module, :call, [[]]}) when is_atom(module), do: module
  defp unruntime({module, :call, [opts]}) when is_atom(module), do: {module, opts}
  defp unruntime({:fn, fun}) when is_function(fun), do: fun

  defimpl Inspect do
    @filtered "[FILTERED]"

    @sensitive_opts %{
      Tesla.Middleware.BasicAuth => [:username, :password],
      Tesla.Middleware.BearerAuth => [:token],
      Tesla.Middleware.DigestAuth => [:username, :password]
    }

    def inspect(%Tesla.Client{} = client, opts) do
      client
      |> Map.update!(:pre, &filter_sensitive_opts/1)
      |> Inspect.Any.inspect(opts)
    end

    defp filter_sensitive_opts(middlewares) do
      Enum.map(middlewares, fn
        {middleware, :call, [opts]} ->
          sensitive_opts = Map.get(@sensitive_opts, middleware, [])
          filtered_opts = Enum.reduce(sensitive_opts, opts, &maybe_redact(&2, &1))
          {middleware, :call, [filtered_opts]}

        middleware ->
          middleware
      end)
    end

    defp maybe_redact(opts, key) do
      cond do
        is_map(opts) and Map.has_key?(opts, key) ->
          Map.put(opts, key, @filtered)

        is_list(opts) and Keyword.has_key?(opts, key) ->
          Keyword.put(opts, key, @filtered)

        true ->
          opts
      end
    end
  end
end
