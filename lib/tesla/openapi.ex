defmodule Tesla.OpenApi do
  @moduledoc """
  Generate API client for given OpenApi specification.

  ### Important notes
  - `operationId` is required to generate API functions

  ### Customization examples

  #### Set the adapter

      defmodule MyApi do
        use Tesla.OpenApi, spec: "path/to/spec.json"

        def new do
          new([], Tesla.Adapter.Mint)
        end
      end

  #### Add middleware

      defmodule MyApi do
        use Tesla.OpenApi, spec: "path/to/spec.json"

        def new do
          middleware = [
            Tesla.Middleware.Telemetry,
            Tesla.Middleware.Logger
          ]

          new(middleware, Tesla.Adapter.Mint)
        end
      end

  #### Setup client with runtime configuration

      defmodule MyApi do
        use Tesla.OpenApi, spec: "path/to/spec.json"

        def new do
          token = Application.get_env(:myapp, :myapi_token)

          middleware = [
            {Tesla.Middleware.BearerAuth, token: token}
          ]

          new(middleware, Tesla.Adapter.Gun)
        end
      end

      MyApi.some_operation()

  #### Setup client with dynamic configuration

      defmodule MyApi do
        use Tesla.OpenApi, spec: "path/to/spec.json"

        def new(token) do
          middleware = [
            {Tesla.Middleware.BearerAuth, token: token}
          ]

          new(middleware, Tesla.Adapter.Gun)
        end
      end

      client = MyApi.new()
      MyApi.some_operation(client)


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
        case op.query_params do
          [] ->
            ""

          qs ->
            list =
              qs
              |> Enum.map(fn
                %{name: name, description: desc} -> "- `#{name}`: #{desc}"
                %{name: name} -> "- `#{name}`"
              end)
              |> Enum.join("\n")

            """
            ### Query parameters

            #{list}
            """
        end

      quote do
        @doc """
        #{unquote(op.summary)}

        #{unquote(op.description)}

        #{unquote(query_doc)}

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
    def encode(schema, var, spec)
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
    def encode(schema, var, spec), do: GenP.encode(schema, var, spec)

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

        @doc """
        See `new/2`.
        """
        @spec new() :: Tesla.Client.t()
        def new(), do: new([], nil)

        @doc """
        Get new API client instance
        """

        @spec new([Tesla.Client.middleware()], Tesla.Client.adapter()) :: Tesla.Client.t()
        def new(middleware, adapter) do
          Tesla.client(@middleware ++ middleware, adapter)
        end

        defoverridable new: 0, new: 2
      end
    end

    defp base_url(spec) do
      url =
        case spec.host do
          "" ->
            spec.base_path

          _ ->
            scheme = if "https" in spec.schemes, do: "https", else: "http"
            scheme <> "://" <> spec.host <> spec.base_path
        end

      {Tesla.Middleware.BaseUrl, url}
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
    end
  end

  defmodule Operation do
    defstruct id: nil,
              path: nil,
              method: nil,
              path_params: [],
              query_params: [],
              body_params: [],
              summary: nil,
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
          case Tesla.request(unquote_splicing(args_out(op, spec))) do
            unquote(matches(op, spec))
          end
        end

        defoverridable unquote([{name(op), length(args_in(op))}])
      end
    end

    defp name(op), do: String.to_atom(Macro.underscore(op.id))

    # TODO: Consider using Macro.unique_var for client and query

    defp args_types(op, spec) do
      [client_type() | path_types(op, spec)] ++ body_type(op, spec) ++ query_type(op)
    end

    defp args_in(op), do: [client_in() | path_in(op)] ++ body_in(op) ++ query_in(op)
    defp args_out(op, spec), do: [client_out(), opts_out(op, spec)]

    defp client_type, do: quote(do: Tesla.Client.t())
    defp client_in, do: quote(do: client \\ new())
    defp client_out, do: quote(do: client)

    defp method_out(op), do: String.to_atom(op.method)

    defp path_types(%{path_params: params}, spec) do
      for %{schema: schema} <- params, do: Gen.type(schema, spec)
    end

    defp path_in(%{path_params: params}) do
      for %{name: name} <- params, do: Macro.var(String.to_atom(name), __MODULE__)
    end

    @path_rx ~r/\{([^}]+?)\}/
    defp path_out(op) do
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

    defp body_type(%{body_params: params}, spec) do
      for %{schema: schema} <- params, do: Gen.type(schema, spec)
    end

    defp body_in(%{body_params: params}) do
      for %{name: name} <- params, do: Macro.var(String.to_atom(name), __MODULE__)
    end

    defp body_out(%{body_params: [%{name: name, schema: schema}]}, spec) do
      var = Macro.var(String.to_atom(name), __MODULE__)
      Gen.encode(schema, var, spec)
    end

    defp query_type(%{query_params: []}), do: []
    defp query_type(%{query_params: _}), do: [quote(do: [opt])]

    defp query_in(%{query_params: []}), do: []
    defp query_in(%{query_params: _}), do: [quote(do: query \\ [])]

    defp query_out(%{query_params: params}) do
      keys =
        Enum.map(params, fn
          %{name: name, format: format} -> {String.to_atom(name), format}
        end)

      quote do
        Tesla.OpenApi.encode_query(query, unquote(keys))
      end
    end

    defp query_types(%{query_params: params}, spec) do
      types =
        params
        |> Enum.map(fn param -> {String.to_atom(param.name), Gen.type(param.schema, spec)} end)
        |> Gen.sumtype()

      [opt: types]
    end

    defp opts_out(op, spec) do
      base = [
        method: method_out(op),
        url: path_out(op)
      ]

      base ++ opts_out_body(op, spec) ++ opts_out_query(op)
    end

    defp opts_out_body(%{body_params: []}, _spec), do: []
    defp opts_out_body(op, spec), do: [body: body_out(op, spec)]

    defp opts_out_query(%{query_params: []}), do: []
    defp opts_out_query(op), do: [query: query_out(op)]

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
              when unquote(query_types(op, spec))
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
      decode = Gen.decode(%{schema | required: true}, var, spec)

      match1 =
        case {code, match} do
          {:default, {:when, [], [body, wh]}} ->
            quote(do: {:ok, %{body: unquote(body)}} when unquote(wh))

          {:default, body} ->
            quote(do: {:ok, %{body: unquote(body)}})

          {status, {:when, [], [body, wh]}} ->
            quote(do: {:ok, %{status: unquote(status), body: unquote(body)}} when unquote(wh))

          {status, body} ->
            quote(do: {:ok, %{status: unquote(status), body: unquote(body)}})
        end

      decode1 =
        case {code, decode} do
          {:default, nil} -> quote(do: :error)
          {:default, decode} -> quote(do: {:error, unquote(decode)})
          {status, nil} when status in 200..299 -> quote(do: :ok)
          {status, decode} when status in 200..299 -> quote(do: {:ok, unquote(decode)})
          {status, nil} -> quote(do: {:error, unquote(status)})
          {_status, decode} -> quote(do: {:error, unquote(decode)})
        end

      {:->, [], [[match1], decode1]}
    end

    defp response_error, do: {:->, [], [[quote(do: {:error, error})], quote(do: {:error, error})]}
    defp response_error_type, do: quote(do: {:error, any})

    defp responses_types(%{responses: responses}, spec) do
      responses
      |> Enum.map(&response_type(&1, spec))
      |> Kernel.++([response_error_type()])
      |> Gen.sumtype()
    end

    defp response_type(%{code: :default, schema: schema}, spec) do
      case Gen.type(schema, spec) do
        nil -> :error
        t -> {:error, t}
      end
    end

    defp response_type(%{code: code, schema: schema}, spec) when code in 200..299 do
      case Gen.type(schema, spec) do
        nil -> :ok
        t -> {:ok, t}
      end
    end

    defp response_type(%{schema: schema}, spec) do
      case Gen.type(schema, spec) do
        nil -> quote(do: {:error, integer})
        t -> {:error, t}
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
      def encode(_schema, var, _spec), do: var
    end
  end

  defmodule Object do
    defstruct name: nil, title: nil, properties: [], required: true

    defimpl GenP do
      def type(%{name: name, properties: properties}, spec) do
        if name && spec.definitions[name] do
          quote(do: unquote(Gen.module_ref(name, spec)).t())
        else
          types = Enum.map(properties, fn p -> {Gen.key(p), Gen.type(p, spec)} end)
          quote(do: %{unquote_splicing(types)})
        end
      end

      def schema(%{name: name, properties: properties} = schema, spec) do
        var = Macro.var(:data, __MODULE__)
        struct = Enum.map(properties, fn p -> {Gen.key(p), nil} end)
        types = Enum.map(properties, fn p -> {Gen.key(p), Gen.type(p, spec)} end)

        quote do
          defmodule unquote(Gen.module_name(name)) do
            unquote(Docs.schema(schema))
            defstruct unquote(struct)
            @type t :: %__MODULE__{unquote_splicing(types)}

            @doc false
            def decode(unquote(var)) do
              # TODO: Move into {:ok, ...} | {:error, ...}
              %__MODULE__{unquote_splicing(decode_props(properties, var, spec))}
            end

            @doc false
            def encode(unquote(var)) do
              %{unquote_splicing(encode_props(properties, var, spec))}
            end
          end
        end
      end

      def match(_schema, var, _spec), do: var

      def decode(%{name: nil, properties: properties}, var, spec) do
        quote do
          %{unquote_splicing(decode_props(properties, var, spec))}
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

      def encode(%{name: nil, properties: properties}, var, spec) do
        quote do
          %{unquote_splicing(decode_props(properties, var, spec))}
        end
      end

      def encode(%{name: name} = schema, var, spec) do
        if spec.definitions[name] do
          quote do
            unquote(Gen.module_ref(name, spec)).encode(unquote(var))
          end
        else
          encode(%{schema | name: nil}, var, spec)
        end
      end

      defp decode_props(properties, var, spec) do
        Enum.map(properties, fn p ->
          {Gen.key(p), Gen.decode(p, quote(do: unquote(var)[unquote(p.name)]), spec)}
        end)
      end

      defp encode_props(properties, var, spec) do
        Enum.map(properties, fn p ->
          {p.name, Gen.encode(p, quote(do: unquote(var).unquote(Gen.key(p))), spec)}
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

      def decode(%{items: %Object{properties: []}}, var, _spec) do
        var
      end

      def decode(%{items: items, required: true}, var, spec) do
        item = Macro.var(:item, __MODULE__)

        quote do
          Enum.map(unquote(var), fn unquote(item) ->
            unquote(GenP.decode(items, item, spec))
          end)
        end
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

      def encode(%{items: nil}, var, _spec) do
        var
      end

      def encode(%{items: %Object{properties: []}}, var, _spec) do
        var
      end

      def encode(%{items: items}, var, spec) do
        item = Macro.var(:item, __MODULE__)

        quote do
          case unquote(var) do
            nil ->
              nil

            _ ->
              Enum.map(unquote(var), fn unquote(item) ->
                unquote(GenP.encode(items, item, spec))
              end)
          end
        end
      end
    end
  end

  defmodule OneOf do
    defstruct name: nil, values: [], required: true

    def collapse(%{values: [single]}), do: single
    def collapse(%{values: [%Primitive{type: "null"}, other]}), do: %{other | required: false}
    def collapse(%{values: [other, %Primitive{type: "null"}]}), do: %{other | required: false}
    def collapse(oneof), do: oneof

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
      def encode(_schema, _var, _spec), do: {:TODO, :OneOfEncode}
    end
  end

  defmodule DefRef do
    defstruct name: nil, ref: nil, required: true

    defimpl GenP do
      def type(%{ref: ref}, spec), do: Gen.type(spec.definitions[ref], spec)
      def match(%{ref: ref}, var, spec), do: Gen.match(spec.definitions[ref], var, spec)
      def schema(_schema, _spec), do: raise("Not Implemented")
      def decode(%{ref: ref}, var, spec), do: Gen.decode(spec.definitions[ref], var, spec)
      def encode(%{ref: ref}, var, spec), do: Gen.encode(spec.definitions[ref], var, spec)
    end
  end

  defmodule AllOf do
    defstruct name: nil, items: [], required: true

    defimpl GenP do
      def type(schema, spec), do: Gen.type(object(schema, spec), spec)
      def schema(schema, spec), do: Gen.schema(object(schema, spec), spec)
      def match(schema, var, spec), do: Gen.match(object(schema, spec), var, spec)
      def decode(schema, var, spec), do: Gen.decode(object(schema, spec), var, spec)
      def encode(schema, var, spec), do: Gen.encode(object(schema, spec), var, spec)

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
      def encode(_schema, _var, _spec), do: nil
    end
  end

  defmodule Unknown do
    defstruct name: nil, schema: nil, required: true

    defimpl GenP do
      def type(_schema, _spec), do: quote(do: any)
      def schema(_schema, _spec), do: nil
      def match(_schema, var, _spec), do: var
      def decode(_schema, var, _spec), do: var
      def encode(_schema, var, _spec), do: var
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
      OneOf.collapse(%OneOf{values: Enum.map(schemas, &load_schema/1)})
    end

    defp load_schema(%{"type" => [_ | _] = types}) when is_list(types) do
      OneOf.collapse(%OneOf{
        values: Enum.map(types, fn type -> load_schema(%{"type" => type}) end)
      })
    end

    defp load_schema(%{"properties" => properties} = spec) do
      %Object{properties: load_properties(properties, spec)}
    end

    defp load_schema(%{"$ref" => "#/definitions/" <> schema}) do
      %DefRef{ref: schema}
    end

    defp load_schema(%{"schema" => schema}) do
      load_schema(schema)
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

      body_params =
        parameters
        |> Enum.filter(&match?(%{"in" => "body"}, &1))
        |> Enum.map(&load_param/1)

      responses =
        operation
        |> Map.get("responses", %{})
        |> Enum.map(fn {code, schema} -> load_response(code, schema) end)

      %Operation{
        query_params: query_params,
        path_params: path_params,
        body_params: body_params,
        responses: responses,
        summary: operation["summary"],
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
      %Response{code: load_code(code), schema: load_schema(schema)}
    end

    defp load_response(code, _) do
      %Response{code: load_code(code), schema: %Empty{}}
    end

    defp load_code("default"), do: :default
    defp load_code(code), do: String.to_integer(code)

    defp load_external_docs(%{"description" => description, "url" => url}) do
      %{description: description, url: url}
    end

    defp load_external_docs(_), do: nil
  end

  defmacro __using__(opts \\ []) do
    file = Keyword.fetch!(opts, :spec)
    dump = Keyword.get(opts, :dump, false)
    spec = Spec.load!(file, __CALLER__.module)

    [
      Gen.module(spec),
      Gen.schemas(spec),
      Operation.generate(spec),
      New.generate(spec)
    ]
    |> tap(&dump(&1, spec, dump))
  end

  defp dump(_code, _spec, false), do: :ok

  defp dump(code, spec, file) do
    code =
      quote do
        defmodule unquote(spec.module) do
          (unquote_splicing(List.flatten(code)))
        end
      end

    bin =
      code
      |> Macro.to_string()
      |> Code.format_string!()

    File.write!(file, bin)
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
