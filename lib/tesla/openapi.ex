defmodule Tesla.OpenApi do
  defmacro __using__(opts \\ []) do
    file = Keyword.fetch!(opts, :spec)
    dump = Keyword.get(opts, :dump, false)

    spec = file |> File.read!() |> Jason.decode!()
    [{config, _}] = Code.compile_quoted(config(__CALLER__.module, opts))

    # use process dict to store caller module and spec
    :erlang.put(:__tesla__caller, __CALLER__.module)
    :erlang.put(:__tesla__spec, spec)

    quote do
      @external_resource unquote(file)
      @moduledoc unquote(doc_module(spec))
      unquote_splicing(models(spec))
      unquote_splicing(operations(spec, config))
      unquote(new(spec))
    end
    # |> print()
    |> dump(dump)
  end

  defp config(mod, opts) do
    op_name =
      case opts[:operations][:name] do
        nil -> quote(do: name)
        fun -> quote(do: unquote(fun).(name))
      end

    generate =
      case opts[:operations][:only] do
        only when is_list(only) -> quote(do: name in unquote(only))
        nil -> quote(do: name)
      end

    quote do
      defmodule unquote(:"#{mod}_config") do
        @moduledoc false
        def op_name(name), do: unquote(op_name)
        def generate?(name), do: unquote(generate)
      end
    end
  end

  defp print(code) do
    code
    |> Macro.to_string()
    |> Code.format_string!()
    |> IO.puts()

    code
  end

  defp dump(code, false), do: code

  defp dump(code, file) do
    caller = :erlang.get(:__tesla__caller)

    bin =
      quote do
        defmodule unquote(caller) do
          unquote(code)
        end
      end
      |> Macro.to_string()
      |> Code.format_string!()

    File.write!(file, bin)
    code
  end

  def decode_list(nil, _fun), do: {:ok, nil}
  def decode_list(list, _fun) when not is_list(list), do: {:ok, list}

  def decode_list(list, fun) do
    list
    |> Enum.reverse()
    |> Enum.reduce({:ok, []}, fn
      data, {:ok, items} ->
        with {:ok, item} <- fun.(data), do: {:ok, [item | items]}

      _, error ->
        error
    end)
  end

  def encode_list(nil, _fun), do: nil
  def encode_list(list, fun), do: Enum.map(list, fun)

  def encode_query(query, keys) do
    Enum.reduce(keys, [], fn
      {key, format}, qs ->
        case query[key] do
          nil -> qs
          val -> Keyword.put(qs, key, encode_query_value(val, format))
        end
    end)
  end

  defp encode_query_value(value, "csv"), do: Enum.join(value, ",")
  defp encode_query_value(value, "int32"), do: value
  defp encode_query_value(value, nil), do: value

  @primitives ["integer", "number", "string", "boolean", "null"]

  ## MODELS

  # 2.x
  defp models(%{"definitions" => defs}), do: models(defs)
  # 3.x
  defp models(%{"components" => %{"schemas" => defs}}), do: models(defs)
  defp models(defs) when is_list(defs), do: Enum.map(defs, &model/1)
  defp models(_spec), do: []

  def model({name, schema}), do: model(name, schema)

  def model(name, %{"type" => type} = schema) when type in @primitives do
    quote do
      @type unquote(var(name)) :: unquote(type(schema))
    end
  end

  def model(name, %{"allOf" => allof}) do
    model(name, %{"type" => "object", "properties" => combine_props(allof)})
  end

  def model(name, %{"type" => "object", "properties" => props} = schema) do
    var = var("data")
    struct = Enum.map(props, fn {name, _} -> {key(name), nil} end)
    types = Enum.map(props, fn {name, prop} -> {key(name), type(prop)} end)

    quote do
      defmodule unquote(defmodule_name(name)) do
        @moduledoc unquote(doc_schema(schema))
        defstruct unquote(struct)
        @type t :: %__MODULE__{unquote_splicing(types)}

        def decode(unquote(var)) do
          with unquote_splicing(decode_props(props, var)) do
            {:ok, %__MODULE__{unquote_splicing(build_props_map(props))}}
          end
        end

        def encode(unquote(var)) do
          %{unquote_splicing(encode_props(props, var))}
        end
      end
    end
  end

  def model(name, schema) do
    var = var("data")

    quote do
      defmodule unquote(defmodule_name(name)) do
        @moduledoc unquote(doc_schema(schema))
        @type t :: unquote(type(schema))
        def decode(unquote(var)), do: unquote(decode(schema, var))
        def encode(unquote(var)), do: unquote(encode(schema, var))
      end
    end
  end

  defp build_props_map(props) do
    for {name, _prop} <- props do
      {key(name), var(name)}
    end
  end

  defp decode_props(props, var) do
    for {name, prop} <- props do
      item = var(name)
      data = quote(do: unquote(var)[unquote(name)])
      {:<-, [], [{:ok, item}, decode(prop, data)]}
    end
  end

  defp encode_props(props, var) do
    for {name, prop} <- props do
      {name, encode(prop, quote(do: unquote(var).unquote(key(name))))}
    end
  end

  defp decode_oneof(schemas, var) do
    for schema <- schemas do
      {:<-, [], [quote(do: {:error, _}), decode(schema, var)]}
    end
  end

  def decode(nil, var), do: {:ok, var}

  def decode(empty, var) when empty == %{}, do: {:ok, var}

  def decode(%{"type" => type}, var) when type in @primitives, do: {:ok, var}

  # TODO: Replace with nullable vars
  def decode(%{"type" => "null"}, var) do
    {:ok, var}
  end

  def decode(%{"type" => "array", "items" => items}, var) when is_list(items) do
    data = var("data")

    quote do
      unquote(__MODULE__).decode_list(unquote(var), fn unquote(data) ->
        with unquote_splicing(decode_oneof(items, data)) do
          {:error, :invalid_value}
        end
      end)
    end
  end

  def decode(%{"type" => "array", "items" => items}, var) do
    data = var("data")

    quote do
      unquote(__MODULE__).decode_list(unquote(var), fn unquote(data) ->
        unquote(decode(items, data))
      end)
    end
  end

  def decode(%{"type" => "array"}, var) do
    quote do
      unquote(__MODULE__).decode_list(unquote(var))
    end
  end

  def decode(%{"allOf" => allof}, var) do
    decode(%{"type" => "object", "properties" => combine_props(allof)}, var)
  end

  def decode(%{"type" => "object", "properties" => props}, var) do
    quote do
      with unquote_splicing(decode_props(props, var)) do
        {:ok, %{unquote_splicing(build_props_map(props))}}
      end
    end
  end

  # TODO: Handle additionalProperties
  def decode(%{"type" => "object"}, var), do: {:ok, var}

  # TODO: Optimize and remove null from types
  # TODO: Optimize when there is only one type in the list
  def decode(%{"type" => [_ | _] = types}, var) do
    schemas = Enum.map(types, fn t -> %{"type" => t} end)

    quote do
      with unquote_splicing(decode_oneof(schemas, var)) do
        {:error, :invalid_value}
      end
    end
  end

  def decode(%{"anyOf" => schemas}, var) when is_list(schemas) do
    quote do
      with unquote_splicing(decode_oneof(schemas, var)) do
        {:error, :invalid_value}
      end
    end
  end

  def decode(%{"items" => schemas}, var) when is_list(schemas) do
    quote do
      with unquote_splicing(decode_oneof(schemas, var)) do
        {:error, :invalid_value}
      end
    end
  end

  def decode(%{"$ref" => ref}, var), do: decode(dereference(ref), var)

  def decode(%{} = schema, _var), do: quote(do: {:unknown, unquote(Macro.escape(schema))})

  def decode({_name, %{"type" => type} = schema}, var) when type in @primitives do
    decode(schema, var)
  end

  def decode({name, _}, var) do
    quote(do: unquote(defmodule_ref(name)).decode(unquote(var)))
  end

  def encode(%{"type" => "array", "items" => items}, var) do
    item = var("item")

    quote do
      unquote(__MODULE__).encode_list(unquote(var), fn unquote(item) ->
        unquote(encode(items, item))
      end)
    end
  end

  def encode(%{"type" => type}, var) when type in @primitives, do: var
  def encode(%{"schema" => schema}, var), do: encode(schema, var)

  def encode(%{"type" => "object", "properties" => props}, var) do
    quote do
      %{unquote_splicing(encode_props(props, var))}
    end
  end

  # TODO: Handle encoding oneof/anyof
  def encode(%{"type" => [_ | _] = _types}, var), do: var
  def encode(%{"items" => _schemas}, var), do: var

  def encode(%{"$ref" => ref}, var), do: encode(dereference(ref), var)

  def encode(%{}, var), do: var

  def encode({_name, %{"type" => type}}, var) when type in @primitives, do: var

  def encode({name, _}, var) do
    quote(do: unquote(defmodule_ref(name)).encode(unquote(var)))
  end

  ## TYPES

  # TODO: Handle required properties

  def type(nil), do: nil
  def type(empty) when empty == %{}, do: quote(do: any)
  def type(%{"type" => "string"}), do: quote(do: binary)
  def type(%{"type" => "boolean"}), do: quote(do: boolean)
  def type(%{"type" => "integer"}), do: quote(do: integer)
  def type(%{"type" => "number"}), do: quote(do: number)
  def type(%{"type" => "null"}), do: nil

  def type(%{"type" => "array", "items" => items}) when is_list(items) do
    types = Enum.map(items, &type(&1))
    quote(do: [unquote(sumtype(types))])
  end

  def type(%{"type" => "array", "items" => items}) do
    quote(do: [unquote(type(items))])
  end

  def type(%{"type" => "array"}), do: quote(do: list)

  def type(%{"schema" => schema}), do: type(schema)
  def type(%{"$ref" => ref}), do: type(dereference(ref))

  def type(%{"allOf" => allof}) do
    type(%{"type" => "object", "properties" => combine_props(allof)})
  end

  def type(%{"type" => "object", "properties" => props}) do
    types = for {name, prop} <- props, do: {key(name), type(prop)}
    quote(do: %{unquote_splicing(types)})
  end

  def type(%{"type" => "object"} = schema) do
    type(Map.put(schema, "properties", []))
  end

  # TODO: Handle oneOf/anyOf types

  def type(%{"type" => [_ | _] = types}) do
    types
    |> Enum.map(fn t -> type(%{"type" => t}) end)
    |> sumtype()
  end

  def type(%{"items" => schemas}) do
    schemas
    |> Enum.map(&type(&1))
    |> sumtype()
  end

  def type(%{}), do: :unknown

  def type({name, %{"type" => type}}) when type in @primitives do
    quote do
      unquote(defmodule_ref()).unquote(var(name))
    end
  end

  def type({name, _}), do: quote(do: unquote(defmodule_ref(name)).t())

  defp sumtype([_ | _] = types) do
    types
    |> Enum.flat_map(&flatsum/1)
    |> Enum.uniq()
    |> Enum.reverse()
    |> Enum.reduce(fn x, xs -> quote(do: unquote(x) | unquote(xs)) end)
  end

  defp flatsum({:|, _, [lhs, rhs]}), do: flatsum(lhs) ++ flatsum(rhs)
  defp flatsum(t), do: [t]

  ## OPERATIONS

  defp operations(spec, config) do
    for {path, methods} <- Map.get(spec, "paths", %{}),
        {method, %{"operationId" => id} = operation} <- methods,
        config.generate?(id) do
      operation(method, path, operation, config)
    end
  end

  def operation(method, path, %{"operationId" => id} = op, config) do
    name = key(config.op_name(id))
    params = dereference_params(op["parameters"] || [])
    args_in = args_in(params)

    quote do
      @doc unquote(doc_operation(op))
      @spec unquote(operation_spec(name, params, op))

      def unquote(name)(unquote_splicing(args_in)) do
        case Tesla.unquote(key(method))(unquote_splicing(args_out(path, params))) do
          unquote(responses(op) ++ catchall())
        end
      end

      defoverridable unquote([{name, length(args_in)}])
    end
  end

  defp operation_spec(name, params, op) do
    if has_query_params?(params) do
      quote do
        unquote(name)(unquote_splicing(args_types(params))) ::
          unquote(responses_types(op))
        when opt: unquote(sumtype(query_types(params)))
      end
    else
      quote do
        unquote(name)(unquote_splicing(args_types(params))) ::
          unquote(responses_types(op))
      end
    end
  end

  defp args_types(params) do
    [client_type()] ++ path_types(params) ++ body_type(params) ++ query_type(params)
  end

  defp args_in(params) do
    [client_in()] ++ path_in(params) ++ body_in(params) ++ query_in(params)
  end

  defp args_out(path, params) do
    [client_out(), path_out(path)] ++ body_out(params) ++ opts_out(params)
  end

  defp client_type, do: quote(do: Tesla.Client.t())
  defp client_in, do: quote(do: client \\ new())
  defp client_out, do: quote(do: client)

  defp path_types(params) do
    for %{"in" => "path"} = param <- params, do: type(param)
  end

  defp path_in(params) do
    for %{"name" => name, "in" => "path"} <- params, do: var(name)
  end

  @path_rx ~r/\{([^}]+?)\}/
  defp path_out(path) do
    Regex.replace(@path_rx, path, fn _, name -> ":" <> Macro.underscore(name) end)
  end

  defp body_type(params) do
    for %{"in" => "body"} = param <- params, do: type(param)
  end

  defp body_in(params) do
    for %{"name" => name, "in" => "body"} <- params, do: var(name)
  end

  defp body_out(params) do
    for %{"name" => name, "in" => "body"} = param <- params, do: encode(param, var(name))
  end

  defp query_type(op), do: if(has_query_params?(op), do: [quote(do: [opt])], else: [])
  defp query_in(op), do: if(has_query_params?(op), do: [quote(do: query \\ [])], else: [])

  defp query_types(params) do
    for %{"name" => name, "in" => "query"} = param <- params do
      {key(name), type(param)}
    end
  end

  defp has_query_params?(params) do
    Enum.any?(params, &match?(%{"in" => "query"}, &1))
  end

  defp opts_out(op) do
    query =
      case query_params(op) do
        [] -> []
        qp -> [query: quote(do: unquote(__MODULE__).encode_query(query, unquote(qp)))]
      end

    opts =
      case path_params(op) do
        [] -> []
        pp -> [opts: [path_params: pp]]
      end

    case query ++ opts do
      [] -> []
      x -> [x]
    end
  end

  defp path_params(params) do
    for %{"name" => name, "in" => "path"} <- params, do: {key(name), var(name)}
  end

  defp query_params(params) do
    for %{"name" => name, "in" => "query"} = p <- params, do: {key(name), p["format"]}
  end

  ## RESPONSES

  defp responses(%{"responses" => responses}) do
    for {status, response} <- responses do
      [match] = response(status, response)
      match
    end
  end

  defp response(code, %{"$ref" => ref}) do
    response(code, dereference(ref))
  end

  defp response(code, %{"content" => content}) do
    # TODO: Handle other/multiple content formats
    response(code, content["application/json"])
  end

  defp response(code, %{"schema" => schema}) do
    body = Macro.var(:body, __MODULE__)
    code = code_or_default(code)
    decode = decode(schema, body)

    case {code, decode} do
      {status, nil} when status in 200..299 ->
        quote do
          {:ok, %{status: unquote(status)}} -> :ok
        end

      {status, decode} when status in 200..299 ->
        quote do
          {:ok, %{status: unquote(status), body: unquote(body)}} -> unquote(decode)
        end

      {status, nil} when is_integer(status) ->
        quote do
          {:ok, %{status: unquote(status)}} -> {:error, unquote(status)}
        end

      {status, decode} when is_integer(status) ->
        quote do
          {:ok, %{status: unquote(status), body: unquote(body)}} ->
            with {:ok, data} <- unquote(decode) do
              {:error, data}
            end
        end

      {:default, nil} ->
        quote do
          {:ok, _} -> :error
        end

      {:default, decode} ->
        quote do
          {:ok, %{body: unquote(body)}} ->
            with {:ok, data} <- unquote(decode) do
              {:error, data}
            end
        end
    end
  end

  defp response(code, %{}) do
    response(code, %{"schema" => nil})
  end

  defp response(code, nil) do
    response(code, %{"schema" => nil})
  end

  defp responses_types(%{"responses" => responses}) do
    responses
    |> Enum.map(fn {status, response} -> response_type(status, response) end)
    |> Kernel.++([catchall_type()])
    |> sumtype()
  end

  defp response_type(code, resp) do
    case {code_or_default(code), type(resp["schema"])} do
      {code, nil} when code in 200..299 -> :ok
      {code, t} when code in 200..299 -> {:ok, t}
      {code, nil} when is_integer(code) -> {:error, quote(do: integer)}
      {code, t} when is_integer(code) -> {:error, t}
      {:default, nil} -> :error
      {:default, t} -> {:error, t}
    end
  end

  defp catchall do
    quote do
      {:error, error} -> {:error, error}
    end
  end

  defp catchall_type, do: quote(do: {:error, any})

  defp code_or_default("default"), do: :default
  defp code_or_default(code), do: String.to_integer(code)

  ## NEW / MIDDLEWARE

  def new(spec) do
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
    host = spec["host"] || ""
    base = spec["basePath"] || ""
    schemas = spec["schemes"] || []

    url =
      case host do
        "" -> base
        _ -> if("https" in schemas, do: "https", else: "http") <> "://" <> host <> base
      end

    [
      {Tesla.Middleware.BaseUrl, url},
      Tesla.Middleware.PathParams
    ]
  end

  defp encoders(spec) do
    Enum.map(spec["consumes"] || [], fn
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

  ## NAMING

  defp key(name), do: name |> Macro.underscore() |> String.replace("/", "_") |> String.to_atom()
  defp var(name), do: Macro.var(key(name), __MODULE__)

  defp defmodule_name(name),
    do: {:__aliases__, [alias: false], [String.to_atom(Macro.camelize(name))]}

  def defmodule_ref(name), do: Module.concat([defmodule_ref(), Macro.camelize(name)])
  def defmodule_ref(), do: :erlang.get(:__tesla__caller)

  ## PROCESSING UTILS

  defp combine_props(allof) do
    Enum.reduce(allof, %{}, fn item, props ->
      Map.merge(props, extract_props(item))
    end)
  end

  defp extract_props(%{"allOf" => allof}), do: combine_props(allof)
  defp extract_props(%{"$ref" => ref}), do: extract_props(dereference(ref))
  defp extract_props(%{"properties" => props}), do: props
  defp extract_props(%{}), do: %{}
  defp extract_props({_name, schema}), do: extract_props(schema)

  defp dereference_params(params) do
    Enum.map(params, fn
      %{"$ref" => ref} -> dereference(ref)
      param -> param
    end)
  end

  def dereference(ref), do: dereference(ref, :erlang.get(:__tesla__spec))

  def dereference(ref, spec) do
    case get_in(spec, compile_path(ref)) do
      nil ->
        raise "Reference #{ref} not found"

      item ->
        # special case for named entities
        case ref do
          "#/definitions/" <> name -> {name, item}
          "#/components/schemas/" <> name -> {name, item}
          _ -> item
        end
    end
  end

  defp compile_path("#/" <> ref) do
    ref
    |> String.split("/")
    |> Enum.map(&unescape/1)
  end

  defp unescape(s) do
    s
    |> String.replace("~0", "~")
    |> String.replace("~1", "/")
    |> URI.decode()
    |> key_or_index()
  end

  defp key_or_index(<<d, _::binary>> = key) when d in ?0..?9 do
    fn
      :get, data, next when is_list(data) ->
        data |> Enum.at(String.to_integer(key)) |> next.()

      :get, data, next when is_map(data) ->
        data |> Map.get(key) |> next.()
    end
  end

  defp key_or_index(key), do: key

  ## DOCS

  defp doc_module(spec) do
    info = spec["info"]

    version =
      case info["version"] do
        nil -> nil
        vsn -> "Version: #{vsn}"
      end

    doc_merge([
      info["title"],
      info["description"],
      version
    ])
  end

  defp doc_schema(schema) do
    doc_merge([
      schema["title"],
      schema["description"]
    ])
  end

  defp doc_operation(op) do
    query_params =
      for {name, %{"in" => "query"} = param} <- op do
        case param["description"] do
          nil -> "- `#{name}`"
          desc -> "- `#{name}`: #{desc}"
        end
      end

    query_docs =
      case query_params do
        [] ->
          nil

        qs ->
          """
          ### Query parameters

          #{Enum.join(qs, "\n")}
          """
      end

    external_docs =
      case op["external_docs"] do
        %{"description" => description, "url" => url} -> "[#{description}](#{url})"
        _ -> nil
      end

    doc_merge([
      op["summary"],
      op["description"],
      query_docs,
      external_docs
    ])
  end

  defp doc_merge(parts) do
    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end
end
