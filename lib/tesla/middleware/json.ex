defmodule Tesla.Middleware.DecodeJson do
  # NOTE: text/javascript added to support Facebook Graph API.
  #       see https://github.com/teamon/tesla/pull/13
  @valid_content_types ["application/json", "text/javascript"]

  def call(env, run, opts \\ []) do
    decode = opts[:decode] || &JSX.decode/1

    env = run.(env)

    if json?(env) do
      {:ok, body} = decode.(to_string(env.body))

      %{env | body: body}
    else
      env
    end
  end

  def json?(env) do
    valid_content_type?(env) && parsable_body?(env)
  end

  def valid_content_type?(env) do
    content_type = to_string(env.headers['Content-Type'])
    Enum.find(@valid_content_types, fn(x) -> String.starts_with?(content_type, x) end)
  end

  def parsable_body?(env) do
    is_binary(env.body) || is_list(env.body)
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
