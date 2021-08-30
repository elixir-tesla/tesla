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
    |> tap(&print/1)
  end

  defp print(x), do: x |> Macro.to_string() |> Code.format_string!() |> IO.puts()

  def gen_schemas(spec) do
    for {name, definition} <- spec["definitions"] do
      props = properties(definition, spec)
      struct = Enum.map(props, fn p -> {p.key, nil} end)
      types = Enum.map(props, fn p -> {p.key, type(p.type, p.required)} end)
      build = Enum.map(props, fn p -> {p.key, quote(do: body[unquote(p.name)])} end)

      quote do
        defmodule unquote({:__aliases__, [alias: false], [String.to_atom(name)]}) do
          defstruct unquote(struct)
          @type t :: %__MODULE__{unquote_splicing(types)}

          def decode(body) do
            %__MODULE__{unquote_splicing(build)}
          end
        end
      end
    end
  end

  defp type(type, true), do: type(type)
  defp type(type, false), do: quote(do: unquote(type(type)) | nil)
  defp type("string"), do: quote(do: binary)
  defp type("integer"), do: quote(do: integer)

  defp properties(%{"properties" => properties} = def, _spec) do
    required = Map.get(def, "required", [])

    for {name, %{"type" => type}} <- properties do
      %{name: name, key: String.to_atom(name), type: type, required: name in required}
    end
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

  defp response_type({:default, %{"schema" => %{"$ref" => "#/definitions/" <> schema}}}) do
    schema = {:__aliases__, [alias: false], [String.to_atom(schema)]}
    quote(do: {:error, unquote(schema).t()})
  end

  defp response_type({:default, _}) do
    nil
  end

  defp response_type(
         {_code,
          %{
            "schema" => %{
              "type" => "array",
              "items" => %{"$ref" => "#/definitions/" <> schema}
            }
          }}
       ) do
    schema = {:__aliases__, [alias: false], [String.to_atom(schema)]}
    quote(do: {:ok, [unquote(schema).t()]})
  end

  defp response_type({_code, %{"schema" => %{"$ref" => "#/definitions/" <> schema}}}) do
    schema = {:__aliases__, [alias: false], [String.to_atom(schema)]}
    quote(do: {:ok, unquote(schema).t()})
  end

  defp response_type({_code, _}) do
    quote(do: :ok)
  end

  defp response_type(:error) do
    quote(do: {:error, any})
  end

  def gen_operations(spec) do
    for {path, methods} <- spec["paths"] do
      for {method, operation} <- methods do
        name = String.to_atom(Macro.underscore(operation["operationId"]))
        {args_in, args_out, args_types, extra_types} = args(path, method, operation)

        responses = Map.get(operation, "responses", %{})
        {default, responses} = Map.pop(responses, "default")

        cases = Map.to_list(responses) ++ [{:default, default}, :error]

        matches =
          cases
          |> Enum.map(&response/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.map(fn {match, resp} -> {:->, [], [[match], resp]} end)

        types =
          cases
          |> Enum.map(&response_type/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.reverse()
          |> Enum.reduce(fn x, xs -> quote(do: unquote(x) | unquote(xs)) end)

        quote do
          unquote(doc(operation))
          unquote(spec(name, args_types, extra_types, types))

          def unquote(name)(unquote_splicing(args_in)) do
            case Tesla.request(unquote_splicing(args_out)) do
              unquote(matches)
            end
          end

          defoverridable unquote([{name, length(args_in)}])
        end
      end
    end
  end

  defp spec(name, args_types, nil, types) do
    quote do
      @spec unquote(name)(unquote_splicing(args_types)) :: unquote(types)
    end
  end

  defp spec(name, args_types, extra_types, types) do
    quote do
      @spec unquote(name)(unquote_splicing(args_types)) :: unquote(types)
            when unquote(extra_types)
    end
  end

  defp doc(operation) do
    parameters = Map.get(operation, "parameters", [])

    query_doc =
      parameters
      |> Enum.filter(&match?(%{"in" => "query"}, &1))
      |> Enum.map(fn
        %{
          "name" => name,
          "description" => desc
        } ->
          "- `#{name}`: #{desc}"
      end)

    quote do
      @doc """
      #{unquote(operation["description"])}

      #{unquote(case query_doc do
        [] -> ""
        qs -> """
          ### Query parameters
      
          #{Enum.join(qs, "\n")}
          """
      end)}
      """
    end
  end

  defp args(path, method, operation) do
    parameters = Map.get(operation, "parameters", [])

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

    path_types =
      parameters
      |> Enum.filter(&match?(%{"in" => "path"}, &1))
      |> Enum.map(fn %{"name" => name, "type" => type} ->
        var = String.to_atom(name)
        quote(do: unquote(Macro.var(var, __MODULE__)) :: unquote(type(type)))
      end)

    path_out = {:<<>>, [], parts}

    query? = Enum.filter(parameters, &match?(%{"in" => "query"}, &1)) != []

    query_params =
      parameters
      |> Enum.filter(&match?(%{"in" => "query"}, &1))
      |> Enum.map(fn
        %{
          "name" => name,
          "type" => "array",
          "items" => %{"type" => type},
          "collectionFormat" => "csv"
        } ->
          {String.to_atom(name), :csv, quote(do: [unquote(type(type))])}

        %{"name" => name, "type" => "array", "items" => %{"type" => type}} ->
          {String.to_atom(name), nil, quote(do: [unquote(type(type))])}

        %{"name" => name, "type" => type} ->
          {String.to_atom(name), nil, type(type)}
      end)

    query_in = quote(do: query \\ [])
    query_type = quote(do: query :: [opt])

    query_out =
      quote do
        Tesla.OpenApi.encode_query(
          query,
          unquote(
            Enum.map(query_params, fn
              {key, nil, _} -> key
              {key, format, _} -> {key, format}
            end)
          )
        )
      end

    query_types =
      if query_params != [] do
        types =
          query_params
          |> Enum.map(fn {k, _, t} -> {k, t} end)
          |> Enum.reduce(fn x, xs -> quote(do: unquote(x) | unquote(xs)) end)

        [opt: types]
      else
        nil
      end

    args_in = [client_in | path_in]
    opts_out = [method: String.to_atom(method), url: path_out]

    args_types = [quote(do: client :: Tesla.client()) | path_types]

    if query? do
      {
        args_in ++ [query_in],
        [client_out, opts_out ++ [query: query_out]],
        args_types ++ [query_type],
        query_types
      }
    else
      {
        args_in,
        [client_out, opts_out],
        args_types,
        nil
      }
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

  def encode_query(query, keys) do
    Enum.reduce(keys, [], fn
      {key, :csv}, qs ->
        case query[key] do
          nil -> qs
          val when is_list(val) -> Keyword.put(qs, key, Enum.join(val, ","))
        end

      key, qs ->
        case query[key] do
          nil -> qs
          val -> Keyword.put(qs, key, val)
        end
    end)
  end
end
