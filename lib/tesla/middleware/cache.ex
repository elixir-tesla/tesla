defmodule Tesla.Middleware.Cache do
  @moduledoc """

  plug Tesla.Middleware.Cache, store: MyStore

  Rewrite of https://github.com/plataformatec/faraday-http-cache
  """

  @behaviour Tesla.Middleware

  defmodule Store do
    @type key :: binary
    @type response :: {Tesla.Env.status(), Tesla.Env.headers(), Tesla.Env.body()}
    @type vary :: binary
    @type data :: response | vary

    @callback get(key) :: {:ok, data} | :not_found
    @callback put(key, data) :: :ok
    @callback delete(key) :: :ok
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
    def cacheable?({_env, %{private?: true}}, false), do: false
    def cacheable?({%{status: status}, _cc}, _) when status in @cacheable_status, do: true
    def cacheable?({_env, _cc}, _), do: false

    def fresh?({env, cc}) do
      cond do
        cc.must_revalidate? -> false
        cc.no_cache? -> false
        true -> ttl({env, cc}) > 0
      end
    end

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
      key = cache_key(req)

      with {:ok, list} <- store.get(key) do
        case Enum.find(list, fn {req0, res} -> valid?(req, req0, res) end) do
          {_, res} -> {:ok, %{req | status: res.status, headers: res.headers, body: res.body}}
          nil -> :not_found
        end
      end
    end

    def put(store, req, res) do
      key = cache_key(req)
      store.put(key, {req, res})
    end

    def delete(store, res) do
      key = cache_key(res)
      store.delete(key)
    end

    defp cache_key(env) do
      :crypto.hash(:sha256, [
        Tesla.build_url(env.url, env.query)
        # Enum.map(env.headers, fn {k, v} -> "#{k}:#{v}" end)
      ])
      |> Base.encode16()
    end

    defp valid?(req, req0, res) do
      case Tesla.get_header(res, "vary") do
        nil -> true
        "*" -> false
        vary -> vary_matches?(req, req0, vary)
      end
    end

    defp vary_matches?(req, req0, vary) do
      vary
      |> String.downcase()
      |> String.split(~r/[\s,]+/)
      |> Enum.all?(fn header ->
        Tesla.get_headers(req, header) == Tesla.get_headers(req0, header)
      end)
    end
  end

  @impl true
  def call(env, next, opts) do
    store = Keyword.fetch!(opts, :store)
    private = Keyword.get(opts, :cache_private, false)
    request = Request.new(env)

    with {:ok, {env, _}} <- process(request, next, store, private) do
      cleanup(env, store)
      {:ok, env}
    end
  end

  defp process(request, next, store, private) do
    if Request.cacheable?(request) do
      if Request.skip_cache?(request) do
        run_and_store(request, next, store, private)
      else
        case fetch(request, store) do
          {:ok, response} ->
            if Response.fresh?(response) do
              {:ok, response}
            else
              with {:ok, response} <- validate(request, response, next) do
                store(request, response, store, private)
              end
            end

          :not_found ->
            run_and_store(request, next, store, private)
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

  defp run_and_store(request, next, store, private) do
    with {:ok, response} <- run(request, next) do
      store(request, response, store, private)
    end
  end

  defp fetch({env, _}, store) do
    case Storage.get(store, env) do
      {:ok, res} -> {:ok, Response.new(res)}
      :not_found -> :not_found
    end
  end

  defp store({req, _} = _request, {res, _} = response, store, private) do
    if Response.cacheable?(response, private) do
      Storage.put(store, req, ensure_date_header(res))
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
