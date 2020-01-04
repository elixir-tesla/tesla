defmodule Tesla.Middleware.DigestAuth do
  @moduledoc """
  Digest access authentication middleware

  [Wiki on the topic](https://en.wikipedia.org/wiki/Digest_access_authentication)

  **NOTE**: Currently the implementation is incomplete and works only for MD5 algorithm
  and auth qop.

  ## Example

  ```
  defmodule MyClient do
    use Tesla

    def client(username, password, opts \\ %{}) do
      Tesla.client([
        {Tesla.Middleware.DigestAuth, Map.merge(%{username: username, password: password}, opts)}
      ])
    end
  end
  ```

  ## Options
  - `:username` - username (defaults to `""`)
  - `:password` - password (defaults to `""`)
  - `:cnonce_fn` - custom function generating client nonce (defaults to `&Tesla.Middleware.DigestAuth.cnonce/0`)
  - `:nc` - nonce counter (defaults to `"00000000"`)
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    if env.opts && Keyword.get(env.opts, :digest_auth_handshake) do
      Tesla.run(env, next)
    else
      opts = opts || %{}

      with {:ok, headers} <- authorization_header(env, opts) do
        env
        |> Tesla.put_headers(headers)
        |> Tesla.run(next)
      end
    end
  end

  defp authorization_header(env, opts) do
    with {:ok, vars} <- authorization_vars(env, opts) do
      {:ok,
       vars
       |> calculated_authorization_values
       |> create_header}
    end
  end

  defp authorization_vars(env, opts) do
    with {:ok, unauthorized_response} <-
           env.__module__.get(
             env.__client__,
             env.url,
             opts: Keyword.put(env.opts || [], :digest_auth_handshake, true)
           ) do
      {:ok,
       %{
         username: opts[:username] || "",
         password: opts[:password] || "",
         path: URI.parse(env.url).path,
         auth:
           Tesla.get_header(unauthorized_response, "www-authenticate")
           |> parse_www_authenticate_header,
         method: env.method |> to_string |> String.upcase(),
         client_nonce: (opts[:cnonce_fn] || (&cnonce/0)).(),
         nc: opts[:nc] || "00000000"
       }}
    end
  end

  defp calculated_authorization_values(%{auth: auth}) when auth == %{}, do: []

  defp calculated_authorization_values(auth_vars) do
    [
      {"username", auth_vars.username},
      {"realm", auth_vars.auth["realm"]},
      {"uri", auth_vars[:path]},
      {"nonce", auth_vars.auth["nonce"]},
      {"nc", auth_vars.nc},
      {"cnonce", auth_vars.client_nonce},
      {"response", response(auth_vars)},
      # hard-coded, will not work for MD5-sess
      {"algorithm", "MD5"},
      # hard-coded, will not work for auth-int or unspecified
      {"qop", "auth"}
    ]
  end

  defp single_header_val({k, v}) when k in ~w(nc qop algorithm), do: "#{k}=#{v}"
  defp single_header_val({k, v}), do: "#{k}=\"#{v}\""

  defp create_header([]), do: []

  defp create_header(calculated_authorization_values) do
    vals =
      calculated_authorization_values
      |> Enum.reduce([], fn val, acc -> [single_header_val(val) | acc] end)
      |> Enum.join(", ")

    [{"authorization", "Digest #{vals}"}]
  end

  defp ha1(%{username: username, auth: %{"realm" => realm}, password: password}) do
    md5("#{username}:#{realm}:#{password}")
  end

  defp ha2(%{method: method, path: path}) do
    md5("#{method}:#{path}")
  end

  defp response(%{auth: %{"nonce" => nonce}, nc: nc, client_nonce: client_nonce} = auth_vars) do
    md5("#{ha1(auth_vars)}:#{nonce}:#{nc}:#{client_nonce}:auth:#{ha2(auth_vars)}")
  end

  defp parse_www_authenticate_header(nil), do: %{}

  defp parse_www_authenticate_header(header) do
    Regex.scan(~r/(\w+?)="(.+?)"/, header)
    |> Enum.reduce(%{}, fn [_, key, val], acc -> Map.merge(acc, %{key => val}) end)
  end

  defp md5(data), do: Base.encode16(:erlang.md5(data), case: :lower)

  defp cnonce, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
