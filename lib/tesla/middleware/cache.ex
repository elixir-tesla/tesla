defmodule Tesla.Middleware.Cache do
  @moduledoc """
  Implementation of HTTP cache

  Rewrite of https://github.com/plataformatec/faraday-http-cache

  ### Example
  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.Cache, store: MyStore
  end
  ```

  ### Options
  - `:store`        - cache store, possible options: `Tesla.Middleware.Cache.Store.Redis`
  - `:mode`         - `:shared` (default) or `:private` (do cache when `Cache-Control: private`)
  """

  @behaviour Tesla.Middleware

  defmodule Store do
    alias Tesla.Env

    @type key :: binary
    @type entry :: {Env.status(), Env.headers(), Env.body(), Env.headers()}
    @type vary :: [binary]
    @type data :: entry | vary
    @type ttl :: integer()
    @type opts :: Keyword.t()

    @callback get(key, opts) :: {:ok, data} | :not_found
    @callback put(key, data, ttl, opts) :: :ok
    @callback delete(key, opts) :: :ok
  end

  defmodule Store.ETS do
    use GenServer

    @behaviour Store

    @ttl_interval :timer.seconds(5)

    def start_link(opts) do
      opts = Keyword.put_new(opts, :name, __MODULE__)
      GenServer.start_link(__MODULE__, opts, opts)
    end

    @impl Store
    def get(key, opts \\ []) do
      case :ets.lookup(table_name(opts), key) do
        [{^key, {_exp, data}} | _rest] -> {:ok, data}
        [] -> :not_found
      end
    end

    @impl Store
    def put(key, data, ttl, opts \\ []) do
      server = Keyword.get(opts, :name, __MODULE__)
      GenServer.call(server, {:put, key, data, ttl})
    end

    @impl Store
    def delete(key, opts \\ []) do
      server = Keyword.get(opts, :name, __MODULE__)
      GenServer.call(server, {:delete, key})
    end

    defp table_name(opts), do: Keyword.get(opts, :name, __MODULE__)

    @impl GenServer
    def init(opts) do
      table_name = table_name(opts)
      :ets.new(table_name, [:named_table])
      Process.send_after(self(), :cleanup, @ttl_interval)
      {:ok, %{current_time: 0, table_name: table_name}}
    end

    @impl GenServer
    def handle_call({:put, key, data, ttl}, _from, state) do
      steps = :erlang.ceil(ttl / @ttl_interval)
      exp = state.current_time + steps
      :ets.insert(state.table_name, {key, {exp, data}})
      {:reply, :ok, state}
    end

    def handle_call({:delete, key}, _from, state) do
      :ets.delete(state.table_name, key)
      {:reply, :ok, state}
    end

    @impl GenServer
    def handle_info(:cleanup, %{current_time: current_time} = state) do
      :ets.tab2list(state.table_name)
      |> Enum.each(fn {key, {exp, _data}} ->
        if current_time > exp, do: :ets.delete(__MODULE__, key)
      end)

      Process.send_after(self(), :cleanup, @ttl_interval)
      {:noreply, %{state | current_time: current_time + 1}}
    end
  end

  defmodule CacheControl do
    @moduledoc false

    defstruct public?: false,
              private?: false,
              no_cache?: false,
              no_store?: false,
              must_revalidate?: false,
              proxy_revalidate?: false,
              max_age: nil,
              s_max_age: nil

    def new(nil), do: %__MODULE__{}
    def new(%Tesla.Env{} = env), do: new(Tesla.get_header(env, "cache-control"))
    def new(header) when is_binary(header), do: parse(header)

    defp parse(header) do
      header
      |> String.trim()
      |> String.split(",")
      |> Enum.reduce(%__MODULE__{}, fn part, cc ->
        part
        |> String.split("=", parts: 2)
        |> Enum.map(&String.trim/1)
        |> case do
          [] -> :ignore
          [key] -> parse(key, "")
          [key, val] -> parse(key, val)
        end
        |> case do
          :ignore -> cc
          {key, val} -> Map.put(cc, key, val)
        end
      end)
    end

    # boolean flags
    defp parse("no-cache", _), do: {:no_cache?, true}
    defp parse("no-store", _), do: {:no_store?, true}
    defp parse("must-revalidate", _), do: {:must_revalidate?, true}
    defp parse("proxy-revalidate", _), do: {:proxy_revalidate?, true}
    defp parse("public", _), do: {:public?, true}
    defp parse("private", _), do: {:private?, true}

    # integers
    defp parse("max-age", val), do: {:max_age, int(val)}
    defp parse("s-maxage", val), do: {:s_max_age, int(val)}

    # others
    defp parse(_, _), do: :ignore

    defp int(bin) do
      case Integer.parse(bin) do
        {int, ""} -> int
        _ -> nil
      end
    end
  end

  defmodule Request do
    def new(env), do: {env, CacheControl.new(env)}

    def cacheable?({%{method: method}, _cc}) when method not in [:get, :head], do: false
    def cacheable?({_env, %{no_store?: true}}), do: false
    def cacheable?({_env, _cc}), do: true

    def skip_cache?({_env, %{no_cache?: true}}), do: true
    def skip_cache?(_), do: false
  end

  defmodule Response do
    def new(env), do: {env, CacheControl.new(env)}

    @cacheable_status [200, 203, 300, 301, 302, 307, 404, 410]
    def cacheable?({_env, %{no_store?: true}}, _), do: false
    def cacheable?({_env, %{private?: true}}, :shared), do: false
    def cacheable?({%{status: status}, _cc}, _) when status in @cacheable_status, do: true
    def cacheable?({_env, _cc}, _), do: false

    def fresh?({env, cc}) do
      cond do
        cc.must_revalidate? -> false
        cc.no_cache? -> false
        true -> ttl({env, cc}) > 0
      end
    end

    def ttl_ms({env, cc}), do: ttl({env, cc}) * 1_000

    defp ttl({env, cc}), do: max_age({env, cc}) - age(env)
    defp max_age({env, cc}), do: cc.s_max_age || cc.max_age || expires(env) || 0
    defp age(env), do: age_header(env) || date_header(env) || 0

    defp expires(env) do
      with header when not is_nil(header) <- Tesla.get_header(env, "expires"),
           {:ok, date} <- Calendar.DateTime.Parse.httpdate(header),
           {:ok, seconds, _, :after} <- Calendar.DateTime.diff(date, DateTime.utc_now()) do
        seconds
      else
        _ -> nil
      end
    end

    defp age_header(env) do
      with bin when not is_nil(bin) <- Tesla.get_header(env, "age"),
           {age, ""} <- Integer.parse(bin) do
        age
      else
        _ -> nil
      end
    end

    defp date_header(env) do
      with bin when not is_nil(bin) <- Tesla.get_header(env, "date"),
           {:ok, date} <- Calendar.DateTime.Parse.httpdate(bin),
           {:ok, seconds, _, :after} <- Calendar.DateTime.diff(DateTime.utc_now(), date) do
        seconds
      else
        _ -> nil
      end
    end
  end

  defmodule Storage do
    def get(store, req) do
      with {:ok, {status, res_headers, body, orig_req_headers}} <- get_by_vary(store, req) do
        if valid?(req.headers, orig_req_headers, res_headers) do
          {:ok, %{req | status: status, headers: res_headers, body: body}}
        else
          :not_found
        end
      end
    end

    defp get_by_vary({store, store_opts}, req) do
      case store.get(key(:vary, req), store_opts) do
        {:ok, [_ | _] = vary} -> store.get(key(:entry, req, vary), store_opts)
        _ -> store.get(key(:entry, req), store_opts)
      end
    end

    def put({store, store_opts}, req, res, ttl) do
      case vary(res.headers) do
        nil ->
          # no Vary, store under URL key
          store.put(key(:entry, req), entry(req, res), ttl, store_opts)

        :wildcard ->
          # * Vary, store under URL key
          store.put(key(:entry, req), entry(req, res), ttl, store_opts)

        vary ->
          # with Vary, store under URL key
          store.put(key(:vary, req), vary, ttl, store_opts)
          store.put(key(:entry, req, vary), entry(req, res), ttl, store_opts)
      end
    end

    def delete({store, store_opts}, req) do
      # check if there is stored vary for this URL
      case store.get(key(:vary, req), store_opts) do
        {:ok, [_ | _] = vary} -> store.delete(key(:entry, req, vary), store_opts)
        _ -> store.delete(key(:entry, req), store_opts)
      end
    end

    defp key(:entry, env), do: key(env) <> ":entry"

    defp key(:vary, env), do: key(env) <> ":vary"

    defp key(:entry, env, vary) do
      headers = vary |> Enum.map(&Tesla.get_header(env, &1)) |> Enum.filter(& &1)
      key(env) <> ":entry:" <> key(headers)
    end

    defp key(%{url: url, query: query}), do: key([Tesla.build_url(url, query)])

    defp key(iodata), do: :crypto.hash(:sha256, iodata) |> Base.encode16()

    defp entry(req, res), do: {res.status, res.headers, res.body, req.headers}

    defp valid?(req_headers, orig_req_headers, res_headers) do
      case vary(res_headers) do
        nil ->
          true

        :wildcard ->
          false

        vary ->
          Enum.all?(vary, fn header ->
            List.keyfind(req_headers, header, 0) == List.keyfind(orig_req_headers, header, 0)
          end)
      end
    end

    defp vary(headers) do
      case List.keyfind(headers, "vary", 0) do
        {_, "*"} ->
          :wildcard

        {_, vary} ->
          vary
          |> String.downcase()
          |> String.split(~r/[\s,]+/)

        _ ->
          nil
      end
    end
  end

  @impl true
  def call(env, next, opts) do
    store = Keyword.fetch!(opts, :store)
    store_opts = Keyword.get(opts, :store_opts, [])
    mode = Keyword.get(opts, :mode, :shared)
    request = Request.new(env)

    with {:ok, {env, _}} <- process(request, next, {store, store_opts}, mode) do
      cleanup(env, {store, store_opts})
      {:ok, env}
    end
  end

  defp process(request, next, store, mode) do
    if Request.cacheable?(request) do
      if Request.skip_cache?(request) do
        run_and_store(request, next, store, mode)
      else
        case fetch(request, store) do
          {:ok, response} ->
            if Response.fresh?(response) do
              {:ok, response}
            else
              with {:ok, response} <- validate(request, response, next) do
                store(request, response, store, mode)
              end
            end

          :not_found ->
            run_and_store(request, next, store, mode)
        end
      end
    else
      run(request, next)
    end
  end

  defp run({env, _} = _request, next) do
    with {:ok, env} <- Tesla.run(env, next) do
      {:ok, Response.new(env)}
    end
  end

  defp run_and_store(request, next, store, mode) do
    with {:ok, response} <- run(request, next) do
      store(request, response, store, mode)
    end
  end

  defp fetch({env, _}, store) do
    case Storage.get(store, env) do
      {:ok, res} -> {:ok, Response.new(res)}
      :not_found -> :not_found
    end
  end

  defp store({req, _} = _request, {res, _} = response, store, mode) do
    if Response.cacheable?(response, mode) do
      Storage.put(store, req, ensure_date_header(res), Response.ttl_ms(response))
    end

    {:ok, response}
  end

  defp ensure_date_header(env) do
    case Tesla.get_header(env, "date") do
      nil -> Tesla.put_header(env, "date", Calendar.DateTime.Format.httpdate(DateTime.utc_now()))
      _ -> env
    end
  end

  defp validate({env, _}, {res, _}, next) do
    env =
      env
      |> maybe_put_header("if-modified-since", Tesla.get_header(res, "last-modified"))
      |> maybe_put_header("if-none-match", Tesla.get_header(res, "etag"))

    case Tesla.run(env, next) do
      {:ok, %{status: 304, headers: headers}} ->
        res =
          Enum.reduce(headers, res, fn
            {k, _}, env when k in ["content-type", "content-length"] -> env
            {k, v}, env -> Tesla.put_header(env, k, v)
          end)

        {:ok, Response.new(res)}

      {:ok, env} ->
        {:ok, Response.new(env)}

      error ->
        error
    end
  end

  defp maybe_put_header(env, _, nil), do: env
  defp maybe_put_header(env, name, value), do: Tesla.put_header(env, name, value)

  @delete_headers ["location", "content-location"]
  defp cleanup(env, store) do
    if delete?(env) do
      for header <- @delete_headers do
        if location = Tesla.get_header(env, header) do
          Storage.delete(store, %{env | url: location})
        end
      end

      Storage.delete(store, env)
    end
  end

  defp delete?(%{method: method}) when method in [:head, :get, :trace, :options], do: false
  defp delete?(%{status: status}) when status in 400..499, do: false
  defp delete?(_env), do: true
end
