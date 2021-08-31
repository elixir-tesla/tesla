defmodule Tesla.OpenApi do
  @moduledoc """
  Generate API client for given OpenApi specification.

  Notes:
  - `operationId` is required to generate API functions
  """

  defmodule Docs do
    def module(spec) do
      quote do
        @moduledoc """
        #{unquote(spec.info.title)}

        #{unquote(spec.info.description)}

        Version #{unquote(spec.info.version)}
        """
      end
    end
  end

  defprotocol GenP do
    def schema(schema, spec)
    def type(schema)
  end

  defmodule Gen do
    def module(spec) do
      quote do
        @external_resource unquote(spec.file)
        unquote(Docs.module(spec))
      end
    end

    def schemas(spec) do
      for {_, definition} <- spec.definitions do
        GenP.schema(definition, spec)
      end
    end

    def type_name(name), do: Macro.var(String.to_atom(name), __MODULE__)

    def type(%{required: false} = schema) do
      sumtype([GenP.type(schema), nil])
    end

    def type(%{required: true} = schema) do
      GenP.type(schema)
    end

    def sumtype(types) do
      types
      |> Enum.flat_map(&flatsum/1)
      |> Enum.uniq()
      |> Enum.reverse()
      |> Enum.reduce(fn x, xs -> quote(do: unquote(x) | unquote(xs)) end)
    end

    defp flatsum({:|, _, [lhs, rhs]}), do: flatsum(lhs) ++ flatsum(rhs)
    defp flatsum(t), do: [t]

    defdelegate schema(schema, spec), to: GenP

    ## UTILS

    def module_name(name) do
      name = Macro.camelize(name)
      {:__aliases__, [alias: false], [String.to_atom(name)]}
    end

    def key(%{name: name}), do: String.to_atom(Macro.underscore(name))
  end

  defmodule Primitive do
    defstruct name: nil, type: nil, format: nil, required: false

    defimpl GenP do
      def type(%{type: "string"}), do: quote(do: binary)
      def type(%{type: "boolean"}), do: quote(do: boolean)
      def type(%{type: "integer"}), do: quote(do: integer)
      def type(%{type: "number"}), do: quote(do: number)
      def type(%{type: "null"}), do: nil

      def schema(%{name: name} = schema, _spec) do
        quote do
          @type unquote(Gen.type_name(name)) :: unquote(type(schema))
        end
      end
    end
  end

  defmodule Object do
    defstruct name: nil, title: nil, properties: [], required: false

    defimpl GenP do
      def type(%{name: nil, properties: _properties}) do
        # TODO: Generate ad-hoc type
        # types = Enum.map(properties, fn p -> {Gen.key(p), Gen.type(p)} end)
        quote(do: map)
      end

      def type(%{name: name}), do: quote(do: unquote(Gen.module_name(name)).t())

      def schema(%{name: name, title: title, properties: properties}, _spec) do
        struct = Enum.map(properties, fn p -> {Gen.key(p), nil} end)
        types = Enum.map(properties, fn p -> {Gen.key(p), Gen.type(p)} end)
        # TODO: Add nested decoding
        build = Enum.map(properties, fn p -> {Gen.key(p), quote(do: body[unquote(p.name)])} end)

        quote do
          defmodule unquote(Gen.module_name(name)) do
            @moduledoc """
            #{unquote(title)}
            """

            defstruct unquote(struct)
            @type t :: %__MODULE__{unquote_splicing(types)}

            def decode(body) do
              # TODO: Move into {:ok, ...} | {:error, ...}
              %__MODULE__{unquote_splicing(build)}
            end
          end
        end
      end
    end
  end

  defmodule Array do
    defstruct name: nil, items: nil, required: false

    defimpl GenP do
      def type(%{items: nil}), do: quote(do: list)
      def type(%{items: items}), do: quote(do: [unquote(Gen.type(items))])

      def schema(%{name: name, items: nil}, _spec) do
        quote do
          @type unquote(Gen.type_name(name)) :: list
        end
      end

      def schema(%{name: name, items: items}, _spec) do
        quote do
          defmodule unquote(Gen.module_name(name)) do
            @type t :: [unquote(Gen.type(items))]

            def decode(items) do
              # TODO: Move into {:ok, ...} | {:error, ...}
              # TODO: Handle decoding
              for item <- items, do: unquote(items).decode(item)
            end
          end
        end
      end
    end
  end

  defmodule OneOf do
    defstruct name: nil, values: [], required: false

    defimpl GenP do
      def type(%{values: values}), do: values |> Enum.map(&Gen.type/1) |> Gen.sumtype()

      def schema(%{name: _name, values: _values}, _spec) do
        # TODO: Handle this
        nil
      end
    end
  end

  defmodule DefRef do
    defstruct name: nil, ref: nil, required: false

    defimpl GenP do
      def type(%{ref: ref}), do: quote(do: unquote(Gen.module_name(ref)).t())
    end
  end

  defmodule AllOf do
    defstruct name: nil, items: [], required: false

    defimpl GenP do
      def schema(%{name: name, items: items}, spec) do
        # compose Object

        properties =
          Enum.flat_map(items, fn
            %Object{properties: properties} ->
              properties

            %DefRef{ref: ref} ->
              %Object{properties: properties} = spec.definitions[ref]
              properties
          end)

        object = %Object{name: name, properties: properties}
        Gen.schema(object, spec)
      end
    end
  end

  defmodule Unknown do
    defstruct name: nil, schema: nil, required: false
  end

  defmodule Spec do
    defstruct file: nil, info: %{}, definitions: %{}, operations: %{}

    def load!(file) do
      json = Jason.decode!(File.read!(file))

      %__MODULE__{
        file: file,
        info: load_info(json),
        definitions: load_definitions(json)
      }
    end

    defp load_info(json) do
      %{
        title: json["info"]["title"],
        description: json["info"]["description"],
        version: json["info"]["version"]
      }
    end

    defp load_definitions(json) do
      json
      |> Map.get("definitions", %{})
      |> Enum.into(%{}, fn {name, spec} ->
        # {name, load_definition(name, spec)}
        {name, %{load_schema(spec) | name: name}}
      end)
    end

    defp load_schema(%{"type" => type} = spec)
         when type in ["integer", "number", "string", "boolean", "null"] do
      %Primitive{type: type, format: spec["format"]}
    end

    defp load_schema(%{"type" => "object", "allOf" => all_of}) do
      %AllOf{items: Enum.map(all_of, &load_schema/1)}
    end

    defp load_schema(%{"type" => "object", "properties" => properties} = spec) do
      %Object{properties: load_properties(properties, spec), title: spec["title"]}
    end

    defp load_schema(%{"type" => "object"} = spec) do
      %Object{title: spec["title"]}
    end

    defp load_schema(%{"type" => "array", "items" => items}) when items === %{} do
      %Array{}
    end

    defp load_schema(%{"type" => "array"}) do
      %Array{}
    end

    defp load_schema(%{"items" => %{"type" => _type} = schema}) do
      %Array{items: load_schema(schema)}
    end

    defp load_schema(%{"items" => schemas}) when is_list(schemas) do
      %OneOf{values: Enum.map(schemas, &load_schema/1)}
    end

    defp load_schema(%{"type" => [_ | _] = types}) when is_list(types) do
      %OneOf{values: Enum.map(types, fn type -> load_schema(%{"type" => type}) end)}
    end

    defp load_schema(%{"properties" => properties} = spec) do
      %Object{properties: load_properties(properties, spec)}
    end

    defp load_schema(%{"$ref" => "#/definitions/" <> schema}) do
      %DefRef{ref: schema}
    end

    defp load_schema(schema) do
      %Unknown{schema: schema}
    end

    defp load_properties(properties, spec) do
      required = Map.get(spec, "required", [])

      for {name, spec} <- properties do
        %{load_schema(spec) | name: name, required: name in required}
      end
    end
  end

  defmacro __using__(opts \\ []) do
    file = Keyword.fetch!(opts, :spec)
    spec = Spec.load!(file)
    # IO.inspect(spec)

    [
      Gen.module(spec),
      Gen.schemas(spec)
      # gen_operations(spec),
      # gen_new(spec)
    ]
    |> tap(&print/1)
  end

  defp print(x), do: x |> Macro.to_string() |> Code.format_string!() |> IO.puts()

  defp module(name) do
    name = Macro.camelize(name)
    {:__aliases__, [alias: false], [String.to_atom(name)]}
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
    quote(do: {:error, unquote(module(schema)).t()})
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
    quote(do: {:ok, [unquote(module(schema)).t()]})
  end

  defp response_type({_code, %{"schema" => %{"$ref" => "#/definitions/" <> schema}}}) do
    quote(do: {:ok, unquote(module(schema)).t()})
  end

  # defp response_type({_code, %{"schema" => %{"properties" => props}}}) do

  # end

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

        if name == :team_info, do: print(cases)

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
