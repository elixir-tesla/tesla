if Code.ensure_loaded?(OpenTelemetry.SemConv.HTTPAttributes) do
  defmodule Tesla.OpenTelemetry.SemConv do
    @moduledoc false

    alias OpenTelemetry.SemConv.ErrorAttributes
    alias OpenTelemetry.SemConv.HTTPAttributes
    alias OpenTelemetry.SemConv.Metrics.HTTPMetrics
    alias OpenTelemetry.SemConv.ServerAttributes
    alias OpenTelemetry.SemConv.URLAttributes

    @method_other "_OTHER"

    @doc false
    @spec build_logger_metadata(Tesla.Env.t(), Tesla.Env.result(), non_neg_integer()) :: map()
    def build_logger_metadata(env, result, time_us)
        when is_integer(time_us) and time_us >= 0 do
      {mapped_method, original} = map_method(env.method)
      duration_ms = Float.round(time_us / 1000.0, 3)

      %{
        HTTPAttributes.http_request_method() => mapped_method,
        HTTPMetrics.http_client_request_duration() => duration_ms
      }
      |> maybe_put_method_original(original)
      |> maybe_put_url(env)
      |> maybe_put_resend_count(env)
      |> maybe_put_http_result(result)
    end

    defp maybe_put_method_original(attrs, nil), do: attrs

    defp maybe_put_method_original(attrs, original),
      do: Map.put(attrs, HTTPAttributes.http_request_method_original(), original)

    defp maybe_put_url(attrs, %Tesla.Env{url: url, query: query}) when is_binary(url) do
      full_url = build_url_full(url, query)

      attrs
      |> Map.put(URLAttributes.url_full(), full_url)
      |> maybe_put_url_parts(full_url)
    end

    defp maybe_put_url(attrs, _env), do: attrs

    defp maybe_put_url_parts(attrs, url) do
      case URI.parse(url) do
        %URI{host: host} = uri when is_binary(host) and host != "" ->
          scheme = uri.scheme || ""
          port = extract_port(uri)

          attrs
          |> Map.put(URLAttributes.url_scheme(), scheme)
          |> Map.put(ServerAttributes.server_address(), host)
          |> Map.put(ServerAttributes.server_port(), port)

        _ ->
          attrs
      end
    end

    defp maybe_put_resend_count(attrs, %Tesla.Env{opts: opts}) do
      case Keyword.get(opts, :retry_count) do
        count when is_integer(count) and count > 0 ->
          Map.put(attrs, HTTPAttributes.http_request_resend_count(), count)

        _ ->
          attrs
      end
    end

    defp maybe_put_resend_count(attrs, _), do: attrs

    defp maybe_put_http_result(attrs, {:ok, %Tesla.Env{status: status}})
         when is_integer(status) do
      attrs = Map.put(attrs, HTTPAttributes.http_response_status_code(), status)

      if status >= 400 do
        Map.put(attrs, ErrorAttributes.error_type(), Integer.to_string(status))
      else
        attrs
      end
    end

    defp maybe_put_http_result(attrs, {:error, reason}) do
      Map.put(attrs, ErrorAttributes.error_type(), error_type_string(reason))
    end

    defp maybe_put_http_result(attrs, _), do: attrs

    defp map_method(:connect), do: {"CONNECT", nil}
    defp map_method(:delete), do: {"DELETE", nil}
    defp map_method(:get), do: {"GET", nil}
    defp map_method(:head), do: {"HEAD", nil}
    defp map_method(:options), do: {"OPTIONS", nil}
    defp map_method(:patch), do: {"PATCH", nil}
    defp map_method(:post), do: {"POST", nil}
    defp map_method(:put), do: {"PUT", nil}
    defp map_method(:trace), do: {"TRACE", nil}

    defp map_method(method) when is_atom(method) do
      {@method_other, method |> Atom.to_string() |> String.upcase()}
    end

    defp map_method(method) when is_binary(method) do
      upcased = String.upcase(method)

      case upcased do
        "CONNECT" -> {"CONNECT", nil}
        "DELETE" -> {"DELETE", nil}
        "GET" -> {"GET", nil}
        "HEAD" -> {"HEAD", nil}
        "OPTIONS" -> {"OPTIONS", nil}
        "PATCH" -> {"PATCH", nil}
        "POST" -> {"POST", nil}
        "PUT" -> {"PUT", nil}
        "TRACE" -> {"TRACE", nil}
        _ -> {@method_other, upcased}
      end
    end

    defp map_method(method), do: {@method_other, inspect(method)}

    defp build_url_full(url, query) do
      url
      |> Tesla.build_url(query)
      |> sanitize_url()
    end

    defp sanitize_url(url) do
      uri = URI.parse(url)

      case uri.userinfo do
        nil -> url
        _ -> %{uri | userinfo: "REDACTED:REDACTED"} |> URI.to_string()
      end
    end

    defp extract_port(%URI{port: port}) when is_integer(port), do: port
    defp extract_port(%URI{scheme: "https"}), do: 443
    defp extract_port(_), do: 80

    defp error_type_string(%{__struct__: struct}), do: inspect(struct)
    defp error_type_string(reason) when is_atom(reason), do: Atom.to_string(reason)
    defp error_type_string(reason) when is_binary(reason), do: reason
    defp error_type_string(_), do: Atom.to_string(ErrorAttributes.error_type_values().other)
  end
end
