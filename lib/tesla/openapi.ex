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

    def schema(%{title: title}) do
      quote do
        @moduledoc """
        #{unquote(title)}
        """
      end
    end

    def operation(op) do
      query_doc =
        op.query_params
        |> Enum.map(fn
          %{name: name, description: desc} -> "- `#{name}`: #{desc}"
          %{name: name} -> "- `#{name}`"
        end)

      quote do
        @doc """
        #{unquote(op.description)}

        #{unquote(case query_doc do
          [] -> ""
          qs -> """
            ### Query parameters
        
            #{Enum.join(qs, "\n")}
            """
        end)}

        #{unquote(case op.external_docs do
          %{description: description, url: url} -> "[#{description}](#{url})"
          _ -> ""
        end)}
        """
      end
    end
  end

  defprotocol GenP do
    def schema(schema, spec)
    def type(schema, spec)
    def match(schema, var, spec)
    def decode(schema, var, spec)
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

    def type(%{required: false} = schema, spec), do: sumtype([GenP.type(schema, spec), nil])
    def type(%{required: true} = schema, spec), do: GenP.type(schema, spec)

    def schema(schema, spec), do: GenP.schema(schema, spec)
    def match(schema, var, spec), do: GenP.match(schema, var, spec)
    def decode(schema, var, spec), do: GenP.decode(schema, var, spec)

    ## UTILS

    def sumtype(types) do
      types
      |> Enum.flat_map(&flatsum/1)
      |> Enum.uniq()
      |> Enum.reverse()
      |> Enum.reduce(fn x, xs -> quote(do: unquote(x) | unquote(xs)) end)
    end

    defp flatsum({:|, _, [lhs, rhs]}), do: flatsum(lhs) ++ flatsum(rhs)
    defp flatsum(t), do: [t]

    def type_name(name), do: Macro.var(String.to_atom(name), __MODULE__)

    def module_name(name) do
      name = Macro.camelize(name)
      {:__aliases__, [alias: false], [String.to_atom(name)]}
    end

    def module_ref(name, spec) do
      name = Macro.camelize(name)
      Module.concat([spec.module, name])
    end

    def key(%{name: name}), do: String.to_atom(Macro.underscore(name))
  end

  defmodule New do
    def generate(spec) do
      middleware = List.flatten([base_url(spec), encoders(spec), decoders(spec)])

      quote do
        @middleware unquote(middleware)
        def new(), do: new([], nil)

        def new(middleware, adapter) do
          Tesla.client(@middleware ++ middleware, adapter)
        end

        defoverridable new: 0, new: 2
      end
    end

    defp base_url(spec) do
      scheme = if "https" in spec.schemes, do: "https", else: "http"
      {Tesla.Middleware.BaseUrl, scheme <> "://" <> spec.host <> spec.base_path}
    end

    defp encoders(spec) do
      Enum.map(spec.consumes, fn
        "application/json" -> Tesla.Middleware.EncodeJson
        _ -> []
      end)
    end

    defp decoders(_spec) do
      [
        Tesla.Middleware.DecodeJson,
        Tesla.Middleware.DecodeFormUrlencoded
      ]

      # Enum.map(spec.produces, fn
      #   "application/json" -> Tesla.Middleware.DecodeJson
      #   _ -> []
      # end)
    end
  end

  defmodule Operation do
    defstruct id: nil,
              path: nil,
              method: nil,
              path_params: [],
              query_params: [],
              description: nil,
              responses: [],
              external_docs: nil

    def generate(%{operations: operations} = spec) do
      for operation <- operations, do: generate(operation, spec)
    end

    def generate(op, spec) do
      quote do
        unquote(Docs.operation(op))
        unquote(spec(op, spec))

        def unquote(name(op))(unquote_splicing(args_in(op))) do
          case Tesla.request(unquote_splicing(args_out(op))) do
            unquote(matches(op, spec))
          end
        end

        defoverridable unquote([{name(op), length(args_in(op))}])
      end
    end

    defp name(op), do: String.to_atom(Macro.underscore(op.id))

    # TODO: Consider using Macro.unique_var for client and query

    defp args_in(op), do: [client_arg_in() | path_args_in(op)] ++ query_arg_in(op)
    defp args_out(op), do: [client_arg_out(), opts_out(op)]

    defp args_types(op, spec) do
      [client_arg_type() | path_args_types(op, spec)] ++ query_arg_type(op)
    end

    defp client_arg_in, do: quote(do: client \\ new())
    defp client_arg_out, do: quote(do: client)
    defp client_arg_type, do: quote(do: Tesla.Client.t())

    defp path_args_in(%{path_params: params}) do
      for %{name: name} <- params, do: Macro.var(String.to_atom(name), __MODULE__)
    end

    defp path_args_types(%{path_params: params}, spec) do
      for %{schema: schema} <- params, do: Gen.type(schema, spec)
    end

    defp query_arg_in(%{query_params: []}), do: []
    defp query_arg_in(%{query_params: _}), do: [quote(do: query \\ [])]
    defp query_arg_type(%{query_params: []}), do: []
    defp query_arg_type(%{query_params: _}), do: [quote(do: [opt])]

    defp query_opts_out(%{query_params: []}), do: []
    defp query_opts_out(op), do: [query: query_opt_out(op)]

    defp query_opt_out(%{query_params: params}) do
      keys =
        Enum.map(params, fn
          %{name: name, format: format} -> {String.to_atom(name), format}
        end)

      quote do
        Tesla.OpenApi.encode_query(query, unquote(keys))
      end
    end

    defp query_opt_type(%{query_params: params}, spec) do
      types =
        params
        |> Enum.map(fn param -> {String.to_atom(param.name), Gen.type(param.schema, spec)} end)
        |> Gen.sumtype()

      [opt: types]
    end

    defp opts_out(op) do
      [
        method: method_opt_out(op),
        url: path_opt_out(op)
      ] ++ query_opts_out(op)
    end

    defp method_opt_out(op), do: String.to_atom(op.method)

    @path_rx ~r/\{([^}]+?)\}/
    defp path_opt_out(op) do
      parts =
        @path_rx
        |> Regex.split(op.path, include_captures: true, trim: true)
        |> Enum.map(fn chunk ->
          case Regex.run(@path_rx, chunk) do
            [_, name] -> {:var, name}
            _ -> chunk
          end
        end)
        |> Enum.map(fn
          {:var, name} ->
            # TODO: Can this be done better?
            var = Macro.var(String.to_atom(name), __MODULE__)
            {:"::", [], [{{:., [], [Kernel, :to_string]}, [], [var]}, {:binary, [], Elixir}]}

          raw ->
            raw
        end)

      {:<<>>, [], parts}
    end

    defp spec(%{query_params: []} = op, spec) do
      quote do
        @spec unquote(name(op))(unquote_splicing(args_types(op, spec))) ::
                unquote(responses_types(op, spec))
      end
    end

    defp spec(op, spec) do
      quote do
        @spec unquote(name(op))(unquote_splicing(args_types(op, spec))) ::
                unquote(responses_types(op, spec))
              when unquote(query_opt_type(op, spec))
      end
    end

    defp matches(%{responses: responses}, spec) do
      responses
      |> Enum.map(&response(&1, spec))
      |> Kernel.++([response_error()])
    end

    defp response(%{code: code, schema: schema}, spec) do
      var = Macro.unique_var(:body, __MODULE__)

      match = Gen.match(schema, var, spec)
      decode = Gen.decode(schema, var, spec)

      {body1, when1} =
        case match do
          {:when, [], [m, w]} -> {m, w}
          m -> {m, nil}
        end

      match1 =
        case code do
          "default" ->
            quote(do: {:ok, %{body: unquote(body1)}})

          code ->
            quote(do: {:ok, %{status: unquote(String.to_integer(code)), body: unquote(body1)}})
        end

      match2 =
        case when1 do
          nil -> match1
          w -> quote(do: unquote(match1) when unquote(w))
        end

      decode1 =
        case code do
          "default" -> :error
          _ -> :ok
        end

      decode2 =
        case decode do
          nil -> decode1
          decode -> {decode1, decode}
        end

      {:->, [], [[match2], decode2]}
    end

    defp response_error, do: {:->, [], [[quote(do: {:error, error})], quote(do: {:error, error})]}
    defp response_error_type, do: quote(do: {:error, any})

    defp responses_types(%{responses: responses}, spec) do
      responses
      |> Enum.map(&response_type(&1, spec))
      |> Kernel.++([response_error_type()])
      |> Gen.sumtype()
    end

    defp response_type(%{code: "default", schema: schema}, spec) do
      case Gen.type(schema, spec) do
        nil -> :error
        t -> {:error, t}
      end
    end

    defp response_type(%{schema: schema}, spec) do
      case Gen.type(schema, spec) do
        nil -> :ok
        t -> {:ok, t}
      end
    end
  end

  defmodule Param do
    defstruct name: nil, required: false, schema: nil, format: nil, description: nil
  end

  defmodule Response do
    defstruct code: nil, schema: nil
  end

  defmodule Primitive do
    defstruct name: nil, type: nil, format: nil, required: true

    defimpl GenP do
      def type(%{type: "string"}, _spec), do: quote(do: binary)
      def type(%{type: "boolean"}, _spec), do: quote(do: boolean)
      def type(%{type: "integer"}, _spec), do: quote(do: integer)
      def type(%{type: "number"}, _spec), do: quote(do: number)
      def type(%{type: "null"}, _spec), do: nil

      def schema(%{name: name} = schema, spec) do
        quote do
          @type unquote(Gen.type_name(name)) :: unquote(type(schema, spec))
        end
      end

      def match(_schema, _var, _spec), do: raise("Not Implemented")
      def decode(_schema, var, _spec), do: var
    end
  end

  defmodule Object do
    defstruct name: nil, title: nil, properties: [], required: true

    defimpl GenP do
      def type(%{name: nil, properties: _properties}, _spec) do
        # TODO: Generate ad-hoc type
        # types = Enum.map(properties, fn p -> {Gen.key(p), Gen.type(p)} end)
        quote(do: map)
      end

      def type(%{name: name}, spec), do: quote(do: unquote(Gen.module_ref(name, spec)).t())

      def schema(%{name: name, properties: properties} = schema, spec) do
        var = Macro.var(:body, __MODULE__)
        struct = Enum.map(properties, fn p -> {Gen.key(p), nil} end)
        types = Enum.map(properties, fn p -> {Gen.key(p), Gen.type(p, spec)} end)

        quote do
          defmodule unquote(Gen.module_name(name)) do
            unquote(Docs.schema(schema))
            defstruct unquote(struct)
            @type t :: %__MODULE__{unquote_splicing(types)}

            def decode(unquote(var)) do
              # TODO: Move into {:ok, ...} | {:error, ...}
              %__MODULE__{unquote_splicing(props_build(properties, var, spec))}
            end
          end
        end
      end

      def match(_schema, var, _spec), do: var

      def decode(%{name: nil, properties: properties}, var, spec) do
        quote do
          %{unquote_splicing(props_build(properties, var, spec))}
        end
      end

      def decode(%{name: name} = schema, var, spec) do
        if spec.definitions[name] do
          quote do
            unquote(Gen.module_ref(name, spec)).decode(unquote(var))
          end
        else
          decode(%{schema | name: nil}, var, spec)
        end
      end

      defp props_build(properties, var, spec) do
        Enum.map(properties, fn p ->
          {Gen.key(p), Gen.decode(p, quote(do: unquote(var)[unquote(p.name)]), spec)}
        end)
      end
    end
  end

  defmodule Array do
    defstruct name: nil, items: nil, required: true

    defimpl GenP do
      def type(%{items: nil}, _spec), do: quote(do: list)
      def type(%{items: items}, spec), do: quote(do: [unquote(Gen.type(items, spec))])

      def schema(%{name: name, items: nil}, _spec) do
        quote do
          @type unquote(Gen.type_name(name)) :: list
        end
      end

      def schema(%{name: name, items: items} = schema, spec) do
        var = Macro.var(:items, __MODULE__)

        quote do
          defmodule unquote(Gen.module_name(name)) do
            @type t :: [unquote(Gen.type(items, spec))]

            def decode(unquote(var)) do
              unquote(decode(schema, var, spec))
            end
          end
        end
      end

      def match(_schema, var, _spec) do
        quote do
          unquote(var) when is_list(unquote(var))
        end
      end

      def decode(%{items: nil}, var, _spec) do
        var
      end

      def decode(%{items: items}, var, spec) do
        item = Macro.var(:item, __MODULE__)

        quote do
          case unquote(var) do
            nil ->
              nil

            _ ->
              Enum.map(unquote(var), fn unquote(item) ->
                unquote(GenP.decode(items, item, spec))
              end)
          end
        end
      end
    end
  end

  defmodule OneOf do
    defstruct name: nil, values: [], required: true

    defimpl GenP do
      def type(%{values: values}, spec) do
        values
        |> Enum.map(&Gen.type(&1, spec))
        |> Gen.sumtype()
      end

      def schema(%{name: _name, values: _values}, _spec) do
        # TODO: Handle this
        nil
      end

      def match(_schema, var, _spec), do: var
      def decode(_schema, _var, _spec), do: {:TODO, :OneOfDecode}
    end
  end

  defmodule DefRef do
    defstruct name: nil, ref: nil, required: true

    defimpl GenP do
      def type(%{ref: ref}, spec), do: Gen.type(spec.definitions[ref], spec)
      def match(%{ref: ref}, var, spec), do: Gen.match(spec.definitions[ref], var, spec)
      def schema(_schema, _spec), do: raise("Not Implemented")
      def decode(%{ref: ref}, var, spec), do: Gen.decode(spec.definitions[ref], var, spec)
    end
  end

  defmodule AllOf do
    defstruct name: nil, items: [], required: true

    defimpl GenP do
      def type(schema, spec), do: Gen.type(object(schema, spec), spec)
      def schema(schema, spec), do: Gen.schema(object(schema, spec), spec)
      def match(schema, var, spec), do: Gen.match(object(schema, spec), var, spec)
      def decode(schema, var, spec), do: Gen.decode(object(schema, spec), var, spec)

      defp object(%{name: name, items: items}, spec) do
        properties =
          Enum.flat_map(items, fn
            %Object{properties: properties} ->
              properties

            %DefRef{ref: ref} ->
              %Object{properties: properties} = spec.definitions[ref]
              properties
          end)

        %Object{name: name, properties: properties}
      end
    end
  end

  defmodule Empty do
    defstruct required: true

    defimpl GenP do
      def type(_schema, _spec), do: nil
      def schema(_schema, _spec), do: nil
      def match(_schema, _var, _spec), do: quote(do: _any)
      def decode(_schema, _var, _spec), do: nil
    end
  end

  defmodule Unknown do
    defstruct name: nil, schema: nil, required: true

    defimpl GenP do
      def type(_schema, _spec), do: quote(do: any)
      def schema(_schema, _spec), do: nil
      def match(_schema, var, _spec), do: var
      def decode(_schema, var, _spec), do: var
    end
  end

  defmodule Spec do
    defstruct module: nil,
              file: nil,
              info: %{},
              host: nil,
              base_path: nil,
              definitions: %{},
              operations: [],
              produces: [],
              consumes: [],
              schemes: []

    def load!(file, module) do
      json = Jason.decode!(File.read!(file))

      %__MODULE__{
        module: module,
        file: file,
        info: load_info(json),
        definitions: load_definitions(json),
        operations: load_operations(json),
        produces: Map.get(json, "produces", []),
        consumes: Map.get(json, "consumes", []),
        schemes: Map.get(json, "schemes", []),
        host: Map.get(json, "host", ""),
        base_path: Map.get(json, "basePath", "/")
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

    defp load_schema(%{"type" => "array", "items" => schema}) do
      %Array{items: load_schema(schema)}
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

    defp load_operations(json) do
      for {path, methods} <- Map.get(json, "paths", %{}),
          {method, %{"operationId" => id} = operation} <- methods do
        %{load_operation(operation) | id: id, path: path, method: method}
      end
    end

    defp load_operation(operation) do
      parameters = Map.get(operation, "parameters", [])

      query_params =
        parameters
        |> Enum.filter(&match?(%{"in" => "query"}, &1))
        |> Enum.map(&load_param/1)

      path_params =
        parameters
        |> Enum.filter(&match?(%{"in" => "path"}, &1))
        |> Enum.map(&load_param/1)

      responses =
        operation
        |> Map.get("responses", %{})
        |> Enum.map(fn {code, schema} -> load_response(code, schema) end)

      %Operation{
        query_params: query_params,
        path_params: path_params,
        responses: responses,
        description: operation["description"],
        external_docs: load_external_docs(operation["externalDocs"])
      }
    end

    defp load_param(%{"name" => name} = spec) do
      %Param{
        name: name,
        required: Map.get(spec, "required", false),
        schema: %{load_schema(spec) | required: true},
        format: load_format(spec["collectionFormat"]),
        description: spec["description"]
      }
    end

    defp load_format("csv"), do: :csv
    defp load_format(nil), do: nil

    defp load_response(code, %{"schema" => schema}) do
      %Response{code: code, schema: load_schema(schema)}
    end

    defp load_response(code, _) do
      %Response{code: code, schema: %Empty{}}
    end

    defp load_external_docs(%{"description" => description, "url" => url}) do
      %{description: description, url: url}
    end

    defp load_external_docs(_), do: nil
  end

  defmacro __using__(opts \\ []) do
    file = Keyword.fetch!(opts, :spec)
    spec = Spec.load!(file, __CALLER__.module)

    [
      Gen.module(spec),
      Gen.schemas(spec),
      Operation.generate(spec),
      New.generate(spec)
    ]
    |> tap(&print/1)
    |> tap(&dump/1)
  end

  defp print(x), do: x |> Macro.to_string() |> Code.format_string!() |> IO.puts()

  defp dump(x) do
    code =
      quote do
        defmodule X do
          (unquote_splicing(List.flatten(x)))
        end
      end

    bin =
      code
      |> Macro.to_string()
      |> Code.format_string!()

    File.write!("tmp/dump.ex", bin)
  end

  def encode_query(query, keys) do
    Enum.reduce(keys, [], fn
      {key, :csv}, qs ->
        case query[key] do
          nil -> qs
          val when is_list(val) -> Keyword.put(qs, key, Enum.join(val, ","))
        end

      {key, nil}, qs ->
        case query[key] do
          nil -> qs
          val -> Keyword.put(qs, key, val)
        end
    end)
  end
end
