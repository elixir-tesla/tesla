defmodule Tesla.Middleware.DecodeJson do
  def call(env, run, opts \\ []) do
    decode = opts[:decode] || &JSX.decode/1

    env = run.(env)

    if is_json_content(env) do
      {:ok, body} = decode.(to_string(env.body))

      %{env | body: body}
    else
      env
    end
  end

  def is_json_content(env) do
    content_type = to_string(env.headers['Content-Type'])
    valid_types = ["application/json", "text/javascript"]
    is_valid_type = Enum.find(valid_types, fn(x) -> String.starts_with?(content_type, x) end)
    is_valid_type && (is_binary(env.body) || is_list(env.body))
  end

end

defmodule Tesla.Middleware.EncodeJson do
  def call(env, run, opts \\ []) do
    encode = opts[:encode] || &JSX.encode/1

    if env.body do
      {:ok, body} = encode.(env.body)

      headers = %{'Content-Type' => 'application/json'}
      env = %{env | body: body}

      Tesla.Middleware.Headers.call(env, run, headers)
    else
      run.(env)
    end
  end
end
