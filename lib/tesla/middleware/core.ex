defmodule Tesla.Middleware.BaseUrl do
  def call(env, next, base) do
    env
    |> apply_base(base)
    |> Tesla.run(next)
  end

  defp apply_base(env, base) do
    if Regex.match?(~r/^https?:\/\//, env.url) do
      env # skip if url is already with scheme
    else
      %{env | url: join(base, env.url)}
    end
  end

  defp join(base, url) do
    case {String.last(to_string(base)), url} do
      {nil, url}          -> url
      {"/", "/" <> rest}  -> base <> rest
      {"/", rest}         -> base <> rest
      {_,   "/" <> rest}  -> base <> "/" <> rest
      {_,   rest}         -> base <> "/" <> rest
    end
  end
end

defmodule Tesla.Middleware.Headers do
  def call(env, next, headers) do
    env
    |> merge(headers)
    |> Tesla.run(next)
  end

  defp merge(env, nil), do: env
  defp merge(env, headers) do
    Map.update!(env, :headers, & Map.merge(&1, headers))
  end
end

defmodule Tesla.Middleware.Query do
  def call(env, next, query) do
    env
    |> merge(query)
    |> Tesla.run(next)
  end

  defp merge(env, nil), do: env
  defp merge(env, query) do
    Map.update!(env, :query, & &1 ++ query)
  end
end

defmodule Tesla.Middleware.DecodeRels do
  def call(env, run, []) do
    env = run.(env)

    if env.headers['Link'] do
      rels = env.headers['Link']
        |> to_string
        |> String.split(",")
        |> Enum.map(&String.strip/1)
        |> Enum.map(fn e -> Regex.run(~r/\A<(.+)>; rel="(.+)"\z/, e, capture: :all_but_first) |> List.to_tuple end)
        |> Enum.reduce(%{}, fn ({url, key}, a) -> Dict.put(a, key, url) end)

      env |> Map.put(:rels, rels)
    else
      env
    end
  end
end

defmodule Tesla.Middleware.AdapterOptions do
  def call(env, run, opts) do
    run.(%{env | opts: env.opts ++ opts})
  end
end

defmodule Tesla.Middleware.BaseUrlFromConfig do
 def call(env, run, opts) do
   run.(%{env | url: config(opts)[:base_url] <> env.url})
 end

 defp config(opts) do
   Application.get_env(Keyword.fetch!(opts, :otp_app), Keyword.fetch!(opts, :module))
 end
end
