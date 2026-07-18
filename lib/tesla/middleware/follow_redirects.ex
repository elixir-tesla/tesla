defmodule Tesla.Middleware.FollowRedirects do
  @moduledoc """
  Follow HTTP 3xx redirects.

  ## Examples

  ```elixir
  defmodule MyClient do
    def client do
    # defaults to 5
      Tesla.client([
        {Tesla.Middleware.FollowRedirects, max_redirects: 3}
      ])
    end
  end
  ```

  ## Options

  - `:max_redirects` - limit number of redirects (default: `5`)
  """

  @behaviour Tesla.Middleware

  @max_redirects 5
  @redirect_statuses [301, 302, 303, 307, 308]

  @impl Tesla.Middleware
  def call(env, next, opts \\ []) do
    max = Keyword.get(opts || [], :max_redirects, @max_redirects)

    redirect(env, next, max)
  end

  defp redirect(env, next, left) when left == 0 do
    case Tesla.run(env, next) do
      {:ok, %{status: status} = env} when status not in @redirect_statuses ->
        {:ok, env}

      {:ok, _env} ->
        {:error, {__MODULE__, :too_many_redirects}}

      error ->
        error
    end
  end

  defp redirect(env, next, left) do
    case Tesla.run(env, next) do
      {:ok, %{status: status} = res} when status in @redirect_statuses ->
        case Tesla.get_header(res, "location") do
          nil ->
            {:ok, res}

          location ->
            prev_uri = URI.parse(env.url)
            next_uri = parse_location(location, res)

            # Copy opts and query params from the response env,
            # these are not modified in the adapters, but middlewares
            # that come after might store state there
            env = %{env | opts: res.opts}

            env
            |> filter_headers(prev_uri, next_uri, status)
            |> new_request(status, URI.to_string(next_uri))
            |> redirect(next, left - 1)
        end

      other ->
        other
    end
  end

  # The 303 (See Other) redirect was added in HTTP/1.1 to indicate that the originally
  # requested resource is not available, however a related resource (or another redirect)
  # available via GET is available at the specified location.
  # https://tools.ietf.org/html/rfc7231#section-6.4.4
  defp new_request(env, 303, location), do: %{env | url: location, method: :get, query: []}

  # The 307 (Temporary Redirect) status code indicates that the target
  # resource resides temporarily under a different URI and the user agent
  # MUST NOT change the request method (...)
  # https://tools.ietf.org/html/rfc7231#section-6.4.7
  defp new_request(env, 307, location), do: %{env | url: location}

  defp new_request(env, _, location), do: %{env | url: location, query: []}

  defp parse_location("https://" <> _rest = location, _env), do: URI.parse(location)
  defp parse_location("http://" <> _rest = location, _env), do: URI.parse(location)
  defp parse_location(location, env), do: env.url |> URI.parse() |> URI.merge(location)

  # Header filtering on redirect, per RFC 9110 §15.4.
  # https://www.rfc-editor.org/rfc/rfc9110.html#section-15.4-5

  # Hop-by-hop and cache-validator headers do not carry over to a new request.
  @always_strip ~w(
    connection
    keep-alive
    proxy-connection
    te
    trailer
    transfer-encoding
    upgrade
    if-match
    if-modified-since
    if-none-match
    if-range
    if-unmodified-since
  )

  # Resource-, origin-, and proxy-specific headers are stripped on cross-origin
  # redirects to avoid leaking credentials or sending values bound to the
  # previous origin.
  @cross_origin_strip ~w(
    authorization
    cookie
    host
    origin
    proxy-authorization
    referer
  )

  # Representation metadata describes the original request body and is no
  # longer applicable when the redirect changes the method (303 -> GET).
  @method_change_strip ~w(
    content-encoding
    content-language
    content-length
    content-location
    content-type
    digest
    last-modified
  )

  defp filter_headers(env, prev, next, status) do
    drop =
      @always_strip
      |> add_if(cross_origin?(prev, next), @cross_origin_strip)
      |> add_if(method_changes?(status), @method_change_strip)

    %{env | headers: Enum.reject(env.headers, &dropped?(&1, drop))}
  end

  defp dropped?({key, _value}, drop), do: String.downcase(to_string(key)) in drop

  defp add_if(list, true, extra), do: list ++ extra
  defp add_if(list, false, _extra), do: list

  defp cross_origin?(prev, next) do
    next.host != prev.host || next.port != prev.port || next.scheme != prev.scheme
  end

  defp method_changes?(303), do: true
  defp method_changes?(_), do: false
end
