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
