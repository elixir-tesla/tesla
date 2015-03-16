defmodule Tesla.Middleware.DecodeJson do
  def call(env, run, []) do
    env = run.(env)

    if is_binary(env.body) do
      {:ok, body} = JSEX.decode(env.body)

      %{env | body: body}
    else
      run.(env)
    end
  end
end

defmodule Tesla.Middleware.EncodeJson do
  def call(env, run, []) do
    if is_binary(env.body) do
      {:ok, body} = JSEX.decode(env.body)

      headers = [{"Content-Type", "application/json"}]
      env = %{env | body: body}

      Tesla.Middleware.Headers.call(env, run, headers)
    else
      run.(env)
    end
  end
end

