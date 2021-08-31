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
    def type(schema)
    def match(schema, var)
    def decode(schema, var)
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

    def type(%{required: false} = schema), do: sumtype([GenP.type(schema), nil])
    def type(%{required: true} = schema), do: GenP.type(schema)

    def schema(schema, spec), do: GenP.schema(schema, spec)

    def match(schema, var), do: GenP.match(schema, var)
    def decode(schema, var), do: GenP.decode(schema, var)

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

    def key(%{name: name}), do: String.to_atom(Macro.underscore(name))
  end

  defmodule New do
    def generate(spec) do
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
      scheme = if "https" in spec.schemes, do: "https", else: "http"
      {Tesla.Middleware.BaseUrl, scheme <> "://" <> spec.host <> spec.base_path}
    end

    defp encoders(spec) do
      Enum.map(spec.consumes, fn
        "application/json" -> Tesla.Middleware.EncodeJson
        _ -> []
      end)
    end

    defp decoders(spec) do
      Enum.map(spec.produces, fn
        "application/json" -> Tesla.Middleware.DecodeJson
        _ -> []
      end)
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

    def generate(%{operations: operations}) do
      for operation <- operations, do: generate(operation)
    end

    def generate(op) do
      quote do
        unquote(Docs.operation(op))
        unquote(spec(op))

        def unquote(name(op))(unquote_splicing(args_in(op))) do
          case Tesla.request(unquote_splicing(args_out(op))) do
            unquote(matches(op))
          end
        end

        defoverridable unquote([{name(op), length(args_in(op))}])
      end
    end

    defp name(op), do: String.to_atom(Macro.underscore(op.id))

    # TODO: Consider using Macro.unique_var for client and query

    defp args_in(op), do: [client_arg_in() | path_args_in(op)] ++ query_arg_in(op)
    defp args_out(op), do: [client_arg_out(), opts_out(op)]
    defp args_types(op), do: [client_arg_type() | path_args_types(op)] ++ query_arg_type(op)

    defp client_arg_in, do: quote(do: client \\ new())
    defp client_arg_out, do: quote(do: client)
    defp client_arg_type, do: quote(do: Tesla.Client.t())

    defp path_args_in(%{path_params: params}) do
      for %{name: name} <- params, do: Macro.var(String.to_atom(name), __MODULE__)
    end

    defp path_args_types(%{path_params: params}) do
      for %{schema: schema} <- params, do: Gen.type(schema)
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

    defp query_opt_type(%{query_params: params}) do
      types =
        params
        |> Enum.map(fn param -> {String.to_atom(param.name), Gen.type(param.schema)} end)
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

    defp spec(%{query_params: []} = op) do
      quote do
        @spec unquote(name(op))(unquote_splicing(args_types(op))) :: unquote(responses_types(op))
      end
    end

    defp spec(op) do
      quote do
        @spec unquote(name(op))(unquote_splicing(args_types(op))) :: unquote(responses_types(op))
              when unquote(query_opt_type(op))
      end
    end

    defp matches(%{responses: responses}) do
      responses
      |> Enum.map(&response/1)
      |> Kernel.++([response_error()])
    end

    defp response(%{code: code, schema: schema}) do
      var = Macro.unique_var(:body, __MODULE__)

      match = Gen.match(schema, var)
      decode = Gen.decode(schema, var)

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

    defp responses_types(%{responses: responses}) do
      responses
      |> Enum.map(&response_type/1)
      |> Kernel.++([response_error_type()])
      |> Gen.sumtype()
    end

    defp response_type(%{code: "default", schema: schema}) do
      case Gen.type(schema) do
        nil -> :error
        t -> {:error, t}
      end
    end

    defp response_type(%{schema: schema}) do
      case Gen.type(schema) do
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

      def match(_schema, _var), do: raise("Not Implemented")
      def decode(_schema, var), do: var
    end
  end

  defmodule Object do
    defstruct name: nil, title: nil, properties: [], required: true

    defimpl GenP do
      def type(%{name: nil, properties: _properties}) do
        # TODO: Generate ad-hoc type
        # types = Enum.map(properties, fn p -> {Gen.key(p), Gen.type(p)} end)
        quote(do: map)
      end

      def type(%{name: name}), do: quote(do: unquote(Gen.module_name(name)).t())

      def schema(%{name: name, properties: properties} = schema, _spec) do
        var = Macro.var(:body, __MODULE__)
        struct = Enum.map(properties, fn p -> {Gen.key(p), nil} end)
        types = Enum.map(properties, fn p -> {Gen.key(p), Gen.type(p)} end)

        quote do
          defmodule unquote(Gen.module_name(name)) do
            unquote(Docs.schema(schema))
            defstruct unquote(struct)
            @type t :: %__MODULE__{unquote_splicing(types)}

            def decode(unquote(var)) do
              # TODO: Move into {:ok, ...} | {:error, ...}
              %__MODULE__{unquote_splicing(props_build(properties, var))}
            end
          end
        end
      end

      def match(_schema, var), do: var

      def decode(%{name: nil, properties: properties}, var) do
        quote do
          %{unquote_splicing(props_build(properties, var))}
        end
      end

      def decode(%{name: name}, var) do
        quote do
          unquote(Gen.module_name(name)).decode(unquote(var))
        end
      end

      defp props_build(properties, var) do
        Enum.map(properties, fn p -> {Gen.key(p), quote(do: unquote(var)[unquote(p.name)])} end)
      end
    end
  end

  defmodule Array do
    defstruct name: nil, items: nil, required: true

    defimpl GenP do
      def type(%{items: nil}), do: quote(do: list)
      def type(%{items: items}), do: quote(do: [unquote(Gen.type(items))])

      def schema(%{name: name, items: nil}, _spec) do
        quote do
          @type unquote(Gen.type_name(name)) :: list
        end
      end

      def schema(%{name: name, items: items} = schema, _spec) do
        var = Macro.var(:items, __MODULE__)

        quote do
          defmodule unquote(Gen.module_name(name)) do
            @type t :: [unquote(Gen.type(items))]

            def decode(unquote(var)) do
              unquote(decode(schema, var))
            end
          end
        end
      end

      def match(_schema, var) do
        quote do
          unquote(var) when is_list(unquote(var))
        end
      end

      def decode(%{items: items}, var) do
        item = Macro.var(:item, __MODULE__)

        quote do
          Enum.map(unquote(var), fn unquote(item) -> unquote(GenP.decode(items, item)) end)
        end
      end
    end
  end

  defmodule OneOf do
    defstruct name: nil, values: [], required: true

    defimpl GenP do
      def type(%{values: values}), do: values |> Enum.map(&Gen.type/1) |> Gen.sumtype()

      def schema(%{name: _name, values: _values}, _spec) do
        # TODO: Handle this
        nil
      end

      def match(_schema, var), do: var
      def decode(_schema, _var), do: {:TODO, :OneOfDecode}
    end
  end

  defmodule DefRef do
    defstruct name: nil, ref: nil, required: true

    defimpl GenP do
      def type(%{ref: ref}), do: quote(do: unquote(Gen.module_name(ref)).t())
      def match(_schema, var), do: var
      def schema(_schema, _spec), do: raise("Not Implemented")

      def decode(%{ref: ref}, var) do
        quote(do: unquote(Gen.module_name(ref)).decode(unquote(var)))
      end
    end
  end

  defmodule AllOf do
    defstruct name: nil, items: [], required: true

    defimpl GenP do
      def type(_schema), do: raise("Not Implemented")

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

      def match(_schema, _var), do: raise("Not Implemented")
      def decode(_schema, _var), do: raise("Not Implemented")
    end
  end

  defmodule Empty do
    defstruct required: true

    defimpl GenP do
      def type(_schema), do: nil
      def schema(_schema, _spec), do: nil
      def match(_schema, _var), do: quote(do: _any)
      def decode(_schema, _var), do: nil
    end
  end

  defmodule Unknown do
    defstruct name: nil, schema: nil, required: true
  end

  defmodule Spec do
    defstruct file: nil,
              info: %{},
              host: nil,
              base_path: nil,
              definitions: %{},
              operations: [],
              produces: [],
              consumes: [],
              schemes: []

    def load!(file) do
      json = Jason.decode!(File.read!(file))

      %__MODULE__{
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
    spec = Spec.load!(file)

    [
      Gen.module(spec),
      Gen.schemas(spec),
      Operation.generate(spec),
      New.generate(spec)
    ]

    # |> tap(&print/1)
  end

  # defp print(x), do: x |> Macro.to_string() |> Code.format_string!() |> IO.puts()

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
