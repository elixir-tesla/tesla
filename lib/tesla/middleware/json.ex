defmodule Tesla.Middleware.DecodeJson do
  def call(env, run, []) do
    env = run.(env)

    content_type = to_string(env.headers['Content-Type'])

    if String.starts_with?(content_type, "application/json") && (is_binary(env.body) || is_list(env.body)) do
      {:ok, body} = JSX.decode(to_string(env.body))

      %{env | body: body}
    else
      env
    end
  end
end

defmodule Tesla.Middleware.EncodeJson do
  def call(env, run, []) do

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
