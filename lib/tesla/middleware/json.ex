defmodule Tesla.Middleware.DecodeJson do
  def call(env, run, nil) do
    env = run.(env)

    if is_binary(env.body) || is_list(env.body) do
      {:ok, body} = JSX.decode(to_string(env.body))

      %{env | body: body}
    else
      env
    end
  end
end

defmodule Tesla.Middleware.EncodeJson do
  def call(env, run, nil) do

    if env.body do
      {:ok, body} = JSX.encode(env.body)

      headers = %{'Content-Type' => 'application/json'}
      env = %{env | body: body}

      Tesla.Middleware.Headers.call(env, run, headers)
    else
      run.(env)
    end
  end
end
