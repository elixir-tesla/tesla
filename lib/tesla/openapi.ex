defmodule Tesla.OpenApi do
  @moduledoc """
  Generate API client for given OpenApi specification.

  Notes:
  - `operationId` is required to generate API functions
  """

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
      case schema(definition, spec) do
        {:list, type} ->
          quote do
            defmodule unquote(module(name)) do
              unquote(doc_schema(definition))
              @type t :: [unquote(type).t()]

              def decode(items) do
                for item <- items, do: unquote(type).decode(item)
              end
            end
          end

        {:struct, props} ->
          struct = Enum.map(props, fn p -> {p.key, nil} end)
          types = Enum.map(props, fn p -> {p.key, p.type} end)
          build = Enum.map(props, fn p -> {p.key, quote(do: body[unquote(p.name)])} end)

          quote do
            defmodule unquote(module(name)) do
              unquote(doc_schema(definition))
              defstruct unquote(struct)
              @type t :: %__MODULE__{unquote_splicing(types)}

              def decode(body) do
                %__MODULE__{unquote_splicing(build)}
              end
            end
          end

        :ignore ->
          []
      end
    end
  end

  defp module(name) do
    name = Macro.camelize(name)
    {:__aliases__, [alias: false], [String.to_atom(name)]}
  end

  defp schema(%{"type" => "array", "items" => %{"$ref" => "#/definitions/" <> schema}}, _spec) do
    {:list, module(schema)}
  end

  defp schema(%{"type" => "array", "items" => items}, _spec) when items === %{} do
    :ignore
  end

  defp schema(%{"items" => _items}, _spec) do
    # TODO: Handle this weird case of items without type=array
    :ignore
  end

  defp schema(%{"type" => "object", "allOf" => all_of}, spec) do
    props =
      Enum.flat_map(all_of, fn
        %{"$ref" => "#/definitions/" <> schema} -> props(spec["definitions"][schema])
        schema -> props(schema)
      end)

    {:struct, props}
  end

  defp schema(%{"properties" => _properties} = def, _spec) do
    {:struct, props(def)}
  end

  defp schema(%{"type" => primitive}, _spec) when primitive in ["string", "boolean", "object"] do
    :ignore
  end

  defp props(%{"properties" => properties} = def) do
    required = Map.get(def, "required", [])

    for {name, map} <- properties do
      %{
        name: name,
        key: String.to_atom(name),
        required: name in required,
        type: prop_type_or_nil(prop_type(map), name in required)
      }
    end
  end

  defp prop_type(%{"type" => [_ | _] = types}) when is_list(types) do
    types
    |> Enum.map(fn type -> prop_type(%{"type" => type}) end)
    |> Enum.reduce(fn x, xs -> quote(do: unquote(x) | unquote(xs)) end)
  end

  defp prop_type(%{"items" => items}) when is_list(items) do
    # treat this as oneOf

    items
    |> Enum.map(fn type -> prop_type(type) end)
    |> Enum.reduce(fn x, xs -> quote(do: unquote(x) | unquote(xs)) end)
  end

  defp prop_type(%{"type" => "null"}), do: quote(do: nil)
  defp prop_type(%{"type" => "string"}), do: quote(do: binary)
  defp prop_type(%{"type" => "integer"}), do: quote(do: integer)
  defp prop_type(%{"type" => "number"}), do: quote(do: number)
  defp prop_type(%{"type" => "boolean"}), do: quote(do: boolean)
  defp prop_type(%{"type" => "object"}), do: quote(do: map)

  defp prop_type(%{"type" => "array", "items" => items}),
    do: quote(do: [unquote(prop_type(items))])

  defp prop_type(%{"type" => "array"}), do: quote(do: list)

  defp prop_type(%{"$ref" => "#/definitions/" <> schema}),
    do: quote(do: unquote(module(schema)).t())

  defp prop_type_or_nil(type, true) do
    type
  end

  defp prop_type_or_nil(type, false) do
    type
    |> flattype()
    |> Enum.reject(&is_nil/1)
    |> Kernel.++([nil])
    |> Enum.reverse()
    |> Enum.reduce(fn x, xs -> quote(do: unquote(x) | unquote(xs)) end)
  end

  defp flattype({:|, _, [lhs, rhs]}), do: flattype(lhs) ++ flattype(rhs)
  defp flattype(t), do: [t]

  defp response({:default, %{"schema" => %{"$ref" => "#/definitions/" <> schema}}}) do
    body = Macro.var(:body, __MODULE__)

    quote do
      {
        {:ok, %{body: unquote(body)}},
        {:error, unquote(module(schema)).decode(unquote(body))}
      }
    end
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

    quote do
      {
        {:ok, %{status: unquote(String.to_integer(code)), body: unquote(body)}}
        when is_list(body),
        {:ok, Enum.map(body, fn item -> unquote(module(schema)).decode(item) end)}
      }
    end
  end

  defp response({code, %{"schema" => %{"$ref" => "#/definitions/" <> schema}}}) do
    body = Macro.var(:body, __MODULE__)

    quote do
      {
        {:ok, %{status: unquote(String.to_integer(code)), body: unquote(body)}},
        {:ok, unquote(module(schema)).decode(unquote(body))}
      }
    end
  end

  defp response({code, _}) do
    quote do
      {
        {:ok, %{status: unquote(String.to_integer(code))}},
        :ok
      }
    end
  end

  defp response(:error) do
    quote do
      {
        {:error, error},
        {:error, error}
      }
    end
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
      for {method, %{"operationId" => operation_id} = operation} <- methods do
        name = String.to_atom(Macro.underscore(operation_id))
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
          unquote(doc_operation(operation))
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

  defp doc_schema(schema) do
    quote do
      @moduledoc """
      #{unquote(schema["title"])}
      """
    end
  end

  defp doc_operation(operation) do
    parameters = Map.get(operation, "parameters", [])

    query_doc =
      parameters
      |> Enum.filter(&match?(%{"in" => "query"}, &1))
      |> Enum.map(fn
        %{"name" => name, "description" => desc} -> "- `#{name}`: #{desc}"
        %{"name" => name} -> "- `#{name}`"
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

      #{unquote(case Map.get(operation, "externalDocs") do
        %{"description" => description, "url" => url} -> "[#{description}](#{url})"
        _ -> ""
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
      |> Enum.map(fn %{"name" => name} = prop ->
        var = String.to_atom(name)
        quote(do: unquote(Macro.var(var, __MODULE__)) :: unquote(prop_type(prop)))
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
          "collectionFormat" => "csv"
        } = prop ->
          {String.to_atom(name), :csv, prop_type(prop)}

        %{"name" => name} = prop ->
          {String.to_atom(name), nil, prop_type(prop)}
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

    args_types = [quote(do: client :: Tesla.Client.t()) | path_types]

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
    Enum.map(spec["consumes"] || [], fn
      "application/json" -> Tesla.Middleware.EncodeJson
      _ -> []
    end)
  end

  defp decoders(spec) do
    Enum.map(spec["produces"] || [], fn
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
