if Code.ensure_loaded?(:hackney) do
  defmodule Tesla.Adapter.Hackney do
    def call(env, opts) do
      with  {:ok, status, headers, body} <- request(env, opts || []) do
        %{env | status:   status,
                headers:  headers,
                body:     body}
      end
    end

    defp request(env, opts) do
      request(
        env.method,
        Tesla.build_url(env.url, env.query),
        Enum.into(env.headers, []),
        env.body,
        opts ++ env.opts
      )
    end
    defp request(method, url, headers, %Stream{} = body, opts), do: request_stream(method, url, headers, body, opts)
    defp request(method, url, headers, body, opts) when is_function(body), do: request_stream(method, url, headers, body, opts)
    defp request(method, url, headers, body, opts) do
      handle :hackney.request(method, url, headers, body || '', opts), opts
    end


    defp request_stream(method, url, headers, body, opts) do
      with {:ok, ref} <- :hackney.request(method, url, headers, :stream, opts) do
        for data <- body, do: :ok = :hackney.send_body(ref, data)
        handle :hackney.start_response(ref), opts
      else
        e -> handle(e, opts)
      end
    end

    defp handle(response, opts) do
      if opts[:stream_response] do
        handle_stream_response(response)
      else
        handle_response(response)
      end
    end

    defp handle_response({:error, _} = error), do: error
    defp handle_response({:ok, status, headers}), do: {:ok, status, headers, []}
    defp handle_response({:ok, status, headers, ref}) do
      with {:ok, body} <- :hackney.body(ref) do
        {:ok, status, headers, body}
      end
    end

    defp handle_stream_response({:error, _} = error), do: error
    defp handle_stream_response({:ok, status, headers}), do: {:ok, status, headers, []}
    defp handle_stream_response({:ok, status, headers, ref}) do
      body = Stream.unfold(ref, fn ref ->
        case :hackney.stream_body(ref) do
          {:ok, ""}         -> nil
          {:ok, data}       -> {data, ref}
          :done             -> nil
          {:error, reason}  -> raise "hackney stream error: #{inspect reason}"
        end
      end)

      {:ok, status, headers, body}
    end
  end
end
