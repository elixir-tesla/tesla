defmodule Tesla.OpenApi do
  defmacro __using__(opts \\ []) do
    file = Keyword.fetch!(opts, :spec)
    spec = Jason.decode!(File.read!(file))

    [
      quote do
        @external_resource unquote(file)
      end,
      gen_schemas(spec),
      gen_operations(spec),
      gen_new(spec)
    ]

    # |> tap(&print/1)
  end

  defp print(x), do: x |> Macro.to_string() |> Code.format_string!() |> IO.puts()

  def gen_schemas(spec) do
    for {name, definition} <- spec["definitions"] do
      props = properties(definition, spec)
      struct = Enum.map(props, fn {key, _} -> {String.to_atom(key), nil} end)

      build =
        Enum.map(props, fn {key, _} -> {String.to_atom(key), quote(do: body[unquote(key)])} end)

      quote do
        defmodule unquote({:__aliases__, [alias: false], [String.to_atom(name)]}) do
          defstruct unquote(struct)

          def decode(body) do
            %__MODULE__{unquote_splicing(build)}
          end
        end
      end
    end
  end

  defp properties(%{"properties" => properties}, _spec) do
    properties
  end

  defp properties(%{"type" => "object", "allOf" => all_of}, spec) do
    Enum.flat_map(all_of, &properties(&1, spec))
  end

  defp properties(%{"$ref" => "#/definitions/" <> schema}, spec) do
    properties(spec["definitions"][schema], spec)
  end

  defp response({:default, %{"schema" => %{"$ref" => "#/definitions/" <> schema}}}) do
    body = Macro.var(:body, __MODULE__)
    schema = {:__aliases__, [alias: false], [String.to_atom(schema)]}

    match =
      quote do
        {:ok, %{body: unquote(body)}}
      end

    resp =
      quote do
        {:error, unquote(schema).decode(unquote(body))}
      end

    {match, resp}
  end

  defp response({:default, _}) do
    nil
  end

  defp response(
         {code,
          %{
            "schema" => %{
              "type" => "array",
              "items" => %{"$ref" => "#/definitions/" <> schema}
            }
          }}
       ) do
    body = Macro.var(:body, __MODULE__)
    schema = {:__aliases__, [alias: false], [String.to_atom(schema)]}

    match =
      quote do
        {:ok, %{status: unquote(String.to_integer(code)), body: unquote(body)}}
        when is_list(body)
      end

    resp =
      quote do
        {:ok, Enum.map(body, fn item -> unquote(schema).decode(item) end)}
      end

    {match, resp}
  end

  defp response({code, %{"schema" => %{"$ref" => "#/definitions/" <> schema}}}) do
    body = Macro.var(:body, __MODULE__)
    schema = {:__aliases__, [alias: false], [String.to_atom(schema)]}

    match =
      quote do
        {:ok, %{status: unquote(String.to_integer(code)), body: unquote(body)}}
      end

    resp =
      quote do
        {:ok, unquote(schema).decode(unquote(body))}
      end

    {match, resp}
  end

  defp response({code, _}) do
    match =
      quote do
        {:ok, %{status: unquote(String.to_integer(code))}}
      end

    resp = :ok
    {match, resp}
  end

  defp response(:error) do
    {quote(do: {:error, error}), quote(do: {:error, error})}
  end

  def gen_operations(spec) do
    for {path, methods} <- spec["paths"] do
      for {method, operation} <- methods do
        name = String.to_atom(Macro.underscore(operation["operationId"]))
        {args_in, args_out} = args(path, method, operation)

        responses = Map.get(operation, "responses", %{})
        {default, responses} = Map.pop(responses, "default")

        responses =
          (Map.to_list(responses) ++ [{:default, default}, :error])
          |> Enum.map(&response/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.map(fn {match, resp} -> {:->, [], [[match], resp]} end)

        quote do
          def unquote(name)(unquote_splicing(args_in)) do
            case Tesla.request(unquote_splicing(args_out)) do
              unquote(responses)
            end
          end

          defoverridable unquote([{name, length(args_in)}])
        end
      end
    end
  end

  defp args(path, method, operation) do
    parameters = Map.get(operation, "parameters", [])
    query? = Enum.filter(parameters, &match?(%{"in" => "query"}, &1)) != []

    parts =
      ~r/\{([^}]+?)\}/
      |> Regex.split(path, include_captures: true, trim: true)
      |> Enum.map(fn x ->
        case Regex.run(~r/\{([^}]+?)\}/, x) do
          [_, name] ->
            {:<<>>, [], [part]} =
              quote(do: "#{unquote(Macro.var(String.to_atom(name), __MODULE__))}")

            part

          _ ->
            x
        end
      end)

    client_in = quote(do: client \\ new())
    client_out = quote(do: client)

    path_in =
      parameters
      |> Enum.filter(&match?(%{"in" => "path"}, &1))
      |> Enum.map(fn %{"name" => name} ->
        var = String.to_atom(name)
        Macro.var(var, __MODULE__)
      end)

    path_out = {:<<>>, [], parts}

    query_in = quote(do: query \\ [])
    query_out = quote(do: query)

    args_in = [client_in | path_in]
    opts_out = [method: String.to_atom(method), url: path_out]

    if query? do
      {args_in ++ [query_in], [client_out, opts_out ++ [query: query_out]]}
    else
      {args_in, [client_out, opts_out]}
    end
  end

  defp gen_new(spec) do
    middleware = List.flatten([base_url(spec), encoders(spec), decoders(spec)])

    quote do
      @middleware unquote(middleware)
      def new(opts \\ []) do
        middleware = Keyword.get(opts, :middleware, [])
        adapter = Keyword.get(opts, :adapter)
        Tesla.client(@middleware ++ middleware, adapter)
      end
    end
  end

  defp base_url(spec) do
    scheme = if "https" in spec["schemes"], do: "https", else: "http"
    {Tesla.Middleware.BaseUrl, scheme <> "://" <> spec["host"] <> spec["basePath"]}
  end

  defp encoders(spec) do
    Enum.map(spec["consumes"], fn
      "application/json" -> Tesla.Middleware.EncodeJson
      _ -> []
    end)
  end

  defp decoders(spec) do
    Enum.map(spec["produces"], fn
      "application/json" -> Tesla.Middleware.DecodeJson
      _ -> []
    end)
  end
end
