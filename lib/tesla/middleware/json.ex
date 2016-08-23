defmodule Tesla.Middleware.DecodeJson do
  # NOTE: text/javascript added to support Facebook Graph API.
  #       see https://github.com/teamon/tesla/pull/13
  @valid_content_types ["application/json", "text/javascript"]

  def call(env, run, opts \\ []) do
    decode = get_decode(opts)

    env = run.(env)

    if json?(env) do
      {:ok, body} = decode.(to_string(env.body))

      %{env | body: body}
    else
      env
    end
  end

  def get_decode(opts) do
    if opts[:decode] do
      opts[:decode]
    else
      engine = opts[:engine] || Poison
      fn e -> apply(engine, :decode, [e, (opts[:opts] || [])]) end
    end
  end

  def json?(env) do
    valid_content_type?(env) && parsable_body?(env)
  end

  def valid_content_type?(env) do
    if ct = find_content_type(env.headers) do
      Enum.find(@valid_content_types, fn(x) -> String.starts_with?(ct, x) end)
    else
      false
    end
  end

  def find_content_type(headers) do
    case Enum.find(headers, fn {k,_} -> String.downcase(to_string(k)) == "content-type" end) do
      {_, ct} -> to_string(ct)
      nil     -> nil
    end
  end

  def parsable_body?(env) do
    is_binary(env.body) || is_list(env.body)
  end
end

defmodule Tesla.Middleware.EncodeJson do
  def call(env, run, opts \\ []) do
    if env.body do
      body    = encode_body(env.body, get_encode(opts))
      headers = %{'Content-Type' => 'application/json'}
      env = %{env | body: body}

      Tesla.Middleware.Headers.call(env, run, headers)
    else
      run.(env)
    end
  end

  def get_encode(opts) do
    if opts[:encode] do
      opts[:encode]
    else
      engine = opts[:engine] || Poison
      fn e -> apply(engine, :encode, [e, (opts[:opts] || [])]) end
    end
  end


  def encode_body(%Stream{} = body, encode_fun), do: encode_body_stream(body, encode_fun)
  def encode_body(body, encode_fun) when is_function(body), do: encode_body_stream(body, encode_fun)
  def encode_body(body, encode_fun) do
    {:ok, body} = encode_fun.(body)
    body
  end

  def encode_body_stream(body, encode_fun) do
    Stream.map body, fn item -> encode_body(item, encode_fun) <> "\n" end
  end
end
