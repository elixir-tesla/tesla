defmodule Tesla.Middleware.FollowRedirects do
  @behaviour Tesla.Middleware

  @moduledoc """
  Follow 3xx redirects

  ### Example
  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.FollowRedirects, max_redirects: 3 # defaults to 5
  end
  ```

  ### Options
  - `:max_redirects` - limit number of redirects (default: `5`)
  - `:force_redirect` - If the server response is 301 or 302, proceed with the redirect even
                        if the original request was neither GET nor HEAD. Default is `false`
  - `:rewrite_method` - If the server responds is 301 or 302, rewrite the method to GET when
                        performing the redirect. This will always set the body to nil.
                        Default is `false`
  - `:preserve_headers` - Preserve the headers from the original request and send them along in the
                          redirect. Default is `false`

  """

  @max_redirects 5
  @force_redirect false
  @rewrite_method false
  @preserve_headers false

  def call(env, next, opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:max_redirects, @max_redirects)
      |> Keyword.put_new(:force_redirect, @force_redirect)
      |> Keyword.put_new(:rewrite_method, @rewrite_method)
      |> Keyword.put_new(:preserve_headers, @preserve_headers)

    # Initial value for remaining attempts
    rem = Keyword.fetch!(opts, :max_redirects)

    process_request(env, next, opts, rem)
  end

  # Status codes 301 and 302 were originally included in HTTP/1.0 and may be responded to
  # differently depending on the user client. Some clients will preserve the original request
  # method, whereas others will follow the redirect with a `GET`. This method attempts to follow
  # the original recommendaiton while allowing the user to override default behavior.
  defp process_response(%{status: status} = env, orig, next, opts, rem)
       when status in [301, 302] do
    method = Map.fetch!(env, :method)
    rewrite_method = Keyword.fetch!(opts, :rewrite_method)
    force_redirect = Keyword.fetch!(opts, :force_redirect)

    with {:ok, env} <- prepare_redirect(orig, env, opts) do
      cond do
        method in [:get, :head] and rewrite_method ->
          process_request(%{env | method: :get, body: nil}, next, opts, rem)

        method in [:get, :head] ->
          process_request(env, next, opts, rem)

        force_redirect and rewrite_method ->
          process_request(%{env | method: :get, body: nil}, next, opts, rem)

        force_redirect ->
          process_request(env, next, opts, rem)

        true ->
          {:ok, orig}
      end
    else
      {:error, {:no_location, env}} -> {:ok, env}
    end
  end

  # Status code 303 is included in the HTTP/1.1 specification and always redirects with `GET`
  defp process_response(%{status: 303} = env, orig, next, opts, rem) do
    with {:ok, env} <- prepare_redirect(orig, env, opts) do
      process_request(%{env | method: :get, body: nil}, next, opts, rem)
    else
      {:error, {:no_location, env}} -> {:ok, env}
    end
  end

  # Status codes 307 and 308 always perform redirects without modifying the original method
  defp process_response(%{status: status} = env, orig, next, opts, rem)
       when status in [307, 308] do
    with {:ok, env} <- prepare_redirect(orig, env, opts) do
      process_request(env, next, opts, rem)
    else
      {:error, {:no_location, env}} -> {:ok, env}
    end
  end

  defp process_response(env, _, _, _, _), do: {:ok, env}

  defp process_request(env, next, opts, rem) when rem >= 0 do
    env
    |> Tesla.run(next)
    |> case do
         {:ok, resp} ->
           process_response(resp, env, next, opts, rem - 1)

         other ->
           other
       end
  end

  defp process_request(_, _, _, _) do
    {:error, {__MODULE__, :too_many_redirects}}
  end

  defp prepare_redirect(orig, env, opts) do
    case Tesla.get_header(env, "location") do
      nil ->
        {:error, {:no_location, env}}

      location ->
        env = %{orig | url: parse_location(location, env), query: []}

        env =
          if Keyword.fetch!(opts, :preserve_headers),
             do: env,
             else: %{env | headers: []}

        {:ok, env}
    end
  end

  defp parse_location("/" <> _rest = location, env) do
    env.url
    |> URI.parse()
    |> URI.merge(location)
    |> URI.to_string()
  end

  defp parse_location(location, _env), do: location
end
