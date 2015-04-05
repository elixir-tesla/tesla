defmodule Tesla.Middleware.BaseUrl do
  def call(env, run, base) do
    run.(%{env | url: base <> env.url})
  end
end

defmodule Tesla.Middleware.Headers do
  def call(env, run, headers) do
    headers = Map.merge(env.headers, headers)
    run.(%{env | headers: headers})
  end
end
