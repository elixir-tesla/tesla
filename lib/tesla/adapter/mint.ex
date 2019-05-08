defmodule Tesla.Adapter.Mint do
  @moduledoc false
  @behaviour Tesla.Adapter
  import Tesla.Adapter.Shared, only: [stream_to_fun: 1, next_chunk: 1]
  alias Mint.HTTP

  @doc false
  def call(env, opts) do
    with {:ok, status, headers, body} <- request(env, opts) do
      {:ok, %{env | status: status, headers: format_headers(headers), body: body}}
    end
  end

  defp format_headers(headers) do
    for {key, value} <- headers do
      {String.downcase(to_string(key)), to_string(value)}
    end
  end

  defp request(env, opts) do
    # Break the URI
    %URI{host: host, scheme: scheme, port: port, path: path, query: query} = URI.parse(env.url)
    query = (query || "") |> URI.decode_query() |> Map.to_list()
    path = Tesla.build_url(path, env.query ++ query)
    method = case env.method do
      :head -> "GET"
      m -> m |> Atom.to_string() |> String.upcase()
    end

    request(
      method,
      scheme,
      host,
      port,
      path,
      env.headers,
      env.body,
      opts
    )
  end
  
  defp request(method, scheme, host, port, path, headers, %Stream{} = body, opts) do
    fun = stream_to_fun(body)
    request(method, scheme, host, port, path, headers, fun, opts)
  end

  defp request(method, scheme, host, port, path, headers, body, opts) when is_function(body) do
    with {:ok, conn} <- HTTP.connect(String.to_atom(scheme), host, port),
         {:ok, conn, req_ref} <- HTTP.request(conn, method, path || "/", headers, :stream),
         {:ok, conn} <- stream_request(conn, req_ref, body),
         {:ok, _conn, res = %{status: status, headers: headers}} <- stream_response(conn) do
      {:ok, status, headers, Map.get(res, :data)}
    end
  end

  defp request(method, scheme, host, port, path, headers, body, opts) do
    with {:ok, conn} <- HTTP.connect(String.to_atom(scheme), host, port),
         {:ok, conn, _req_ref} <- HTTP.request(conn, method, path || "/", headers, body || ""),
         {:ok, _conn, res = %{status: status, headers: headers}} <- stream_response(conn) do
      {:ok, status, headers, Map.get(res, :data)}
    end
  end

  defp stream_request(conn, req_ref, fun) do
    case next_chunk(fun) do
      {:ok, item, fun} ->
        HTTP.stream_request_body(conn, req_ref, item)
        stream_request(conn, req_ref, fun)
      :eof ->
        HTTP.stream_request_body(conn, req_ref, :eof)
    end
  end

  defp stream_response(conn, response \\ %{}) do
    receive do
      msg ->
        case HTTP.stream(conn, msg) do
          {:ok, conn, stream} ->
            response =
              Enum.reduce(stream, response, fn x, acc ->
                case x do
                  {:status, _req_ref, code} ->
                    Map.put(acc, :status, code)

                  {:headers, _req_ref, headers} ->
                    Map.put(acc, :headers, headers)

                  {:data, _req_ref, data} ->
                    Map.put(acc, :data, Map.get(acc, :data, "") <> data)

                  {:done, _req_ref} ->
                    Map.put(acc, :done, true)
                end
              end)

            if Map.get(response, :done) do
              response = Map.drop(response, [:done])
              {:ok, conn, response}
            else
              stream_response(conn, response)
            end

          _ ->
            {:error, "TODO: Error Handle"}
        end
    end
  end
end
