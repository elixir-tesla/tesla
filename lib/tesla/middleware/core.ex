defmodule Tesla.Middleware.BaseUrl do
  def call(env, run, base) do
    env = if !Regex.match?(~r/^https?:\/\//, env.url) do
      %{env | url: base <> env.url}
    else
      env
    end

    run.(env)
  end
end

defmodule Tesla.Middleware.Headers do
  def call(env, run, headers) do
    headers = Map.merge(env.headers, headers)
    run.(%{env | headers: headers})
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
