defmodule Tesla.Adapter.Httpc do
  @moduledoc """
  Adapter for [httpc](http://erlang.org/doc/man/httpc.html).

  This is the default adapter.

  **NOTE** Tesla overrides default autoredirect value with false to ensure
  consistency between adapters
  """

  @behaviour Tesla.Adapter
  import Tesla.Adapter.Shared, only: [stream_to_fun: 1, next_chunk: 1]
  alias Tesla.Multipart

  @override_defaults autoredirect: false
  @http_opts ~w(timeout connect_timeout ssl essl autoredirect proxy_auth version relaxed url_encode)a

  @impl Tesla.Adapter
  def call(env, opts) do
    opts = Tesla.Adapter.opts(@override_defaults, env, opts)

    with {:ok, {status, headers, body}} <- request(env, opts) do
      {:ok, format_response(env, status, headers, body)}
    end
  end

  defp format_response(env, {_, status, _}, headers, body) do
    %{env | status: status, headers: format_headers(headers), body: format_body(body)}
  end

  # from http://erlang.org/doc/man/httpc.html
  #   headers() = [header()]
  #   header() = {field(), value()}
  #   field() = string()
  #   value() = string()
  defp format_headers(headers) do
    for {key, value} <- headers do
      {String.downcase(to_string(key)), to_string(value)}
    end
  end

  # from http://erlang.org/doc/man/httpc.html
  #   string() = list of ASCII characters
  #   Body = string() | binary()
  defp format_body(data) when is_list(data), do: IO.iodata_to_binary(data)
  defp format_body(data) when is_binary(data), do: data

  defp request(env, opts) do
    content_type = to_charlist(Tesla.get_header(env, "content-type") || "")

    handle(
      request(
        env.method,
        Tesla.build_url(env.url, env.query) |> to_charlist,
        Enum.map(env.headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end),
        content_type,
        env.body,
        Keyword.split(opts, @http_opts)
      )
    )
  end

  # fix for # see https://github.com/teamon/tesla/issues/147
  defp request(:delete, url, headers, content_type, nil, {http_opts, opts}) do
    request(:delete, url, headers, content_type, "", {http_opts, opts})
  end

  defp request(method, url, headers, _content_type, nil, {http_opts, opts}) do
    :httpc.request(method, {url, headers}, http_opts, opts)
  end

  # These methods aren't able to contain a content_type and body
  defp request(method, url, headers, _content_type, _body, {http_opts, opts})
       when method in [:get, :options, :head, :trace] do
    :httpc.request(method, {url, headers}, http_opts, opts)
  end

  defp request(method, url, headers, _content_type, %Multipart{} = mp, opts) do
    headers = headers ++ Multipart.headers(mp)
    headers = for {key, value} <- headers, do: {to_charlist(key), to_charlist(value)}

    {content_type, headers} =
      case List.keytake(headers, 'content-type', 0) do
        nil -> {'text/plain', headers}
        {{_, ct}, headers} -> {ct, headers}
      end

    body = stream_to_fun(Multipart.body(mp))

    request(method, url, headers, to_charlist(content_type), body, opts)
  end

  defp request(method, url, headers, content_type, %Stream{} = body, opts) do
    fun = stream_to_fun(body)
    request(method, url, headers, content_type, fun, opts)
  end

  defp request(method, url, headers, content_type, body, opts) when is_function(body) do
    body = {:chunkify, &next_chunk/1, body}
    request(method, url, headers, content_type, body, opts)
  end

  defp request(method, url, headers, content_type, body, {http_opts, opts}) do
    :httpc.request(method, {url, headers, content_type, body}, http_opts, opts)
  end

  defp handle({:error, {:failed_connect, _}}), do: {:error, :econnrefused}
  defp handle(response), do: response
end
