defmodule Tesla.OpenApi.Gen do
  alias Tesla.OpenApi.{Prim, Union, Array, Object, Ref, Any}
  alias Tesla.OpenApi.{Model, Operation, Response}
  alias Tesla.OpenApi.{Spec, Context, Clean, Doc}

  ## GEN

  def gen(%Spec{} = spec) do
    models = Clean.clean(Enum.map(spec.models, &model/1))
    operations = Clean.clean(Enum.map(spec.operations, &operation/1))
    new = new(spec)

    quote do
      @moduledoc unquote(Doc.module(spec.info))
      unquote_splicing(models)
      unquote_splicing(operations)
      unquote(new)
    end
  end

  ## TYPES

  def type(%Prim{type: :null}), do: quote(do: nil)
  def type(%Prim{type: :binary}), do: quote(do: binary)
  def type(%Prim{type: :boolean}), do: quote(do: boolean)
  def type(%Prim{type: :integer}), do: quote(do: integer)
  def type(%Prim{type: :number}), do: quote(do: number)
  def type(%Union{of: of}), do: uniontypes(Enum.map(of, &type/1))
  def type(%Any{}), do: quote(do: any)
  def type(%Array{of: %Any{}}), do: quote(do: list)
  def type(%Array{of: of}), do: quote(do: list(unquote(type(of))))

  def type(%Object{props: props}) do
    types = for {name, prop} <- props, do: {key(name), type(prop)}
    quote(do: %{unquote_splicing(types)})
  end

  def type(%Ref{name: name, ref: ref}) do
    if moduleless?(Spec.fetch(ref)) do
      quote(do: unquote(moduleref()).unquote(var(name)))
    else
      quote(do: unquote(moduleref(name)).t())
    end
  end

  def type(%Response{code: :default, schema: nil}), do: :error
  def type(%Response{code: :default, schema: s}), do: {:error, type(s)}
  def type(%Response{code: code, schema: nil}) when code in 200..299, do: :ok
  def type(%Response{code: code, schema: s}) when code in 200..299, do: {:ok, type(s)}
  def type(%Response{code: code, schema: nil}) when is_integer(code), do: {:error, var("integer")}
  def type(%Response{code: code, schema: s}) when is_integer(code), do: {:error, type(s)}

  def type(%Operation{} = op) do
    name = key(op.id)

    args =
      flatten_once([
        type_client(),
        type_path_params(op),
        type_body_params(op),
        type_query_params(op)
      ])

    resps = type_responses(op)

    case op.query_params do
      [] ->
        quote do
          unquote(name)(unquote_splicing(args)) :: unquote(resps)
        end

      _ ->
        quote do
          unquote(name)(unquote_splicing(args)) :: unquote(resps)
          when opt: unquote(type_query_opts(op))
        end
    end
  end

  defp type_client, do: quote(do: Tesla.Client.t())
  defp type_path_params(%{path_params: params}), do: Enum.map(params, &type(&1.schema))
  defp type_body_params(%{request_body: %{} = schema}), do: type(schema)
  defp type_body_params(%{body_params: params}), do: Enum.map(params, &type(&1.schema))
  defp type_query_params(%{query_params: []}), do: []
  defp type_query_params(%{query_params: _}), do: quote(do: [[opt]])

  defp type_query_opts(%{query_params: params}) do
    params
    |> Enum.map(fn %{name: name, schema: schema} -> {key(name), type(schema)} end)
    |> uniontypes
  end

  defp type_responses(%{responses: responses}) do
    uniontypes(Enum.map(responses, &type/1) ++ [type_catchall()])
  end

  defp type_catchall, do: quote(do: {:error, any})

  defp uniontypes([_ | _] = types) do
    types
    |> Enum.flat_map(&unnest/1)
    |> Enum.uniq()
    |> Enum.reverse()
    |> Enum.reduce(fn x, xs -> quote(do: unquote(x) | unquote(xs)) end)
  end

  defp unnest({:|, _, [lhs, rhs]}), do: unnest(lhs) ++ unnest(rhs)
  defp unnest(t), do: [t]

  ## ENCODE

  def encode(%Prim{}, var), do: var
  def encode(%Any{}, var), do: var

  def encode(%Ref{name: name, ref: ref}, var) do
    schema = Spec.fetch(ref)

    if moduleless?(schema) do
      encode(schema, var)
    else
      quote(do: unquote(moduleref(name)).encode(unquote(var)))
    end
  end

  def encode(%Union{of: of}, var) do
    quote do
      cond do
        unquote(Enum.map(of, fn s -> right(match(s, var), encode(s, var)) end))
      end
    end
  end

  def encode(%Array{of: of}, var) do
    item = var("item")

    quote do
      Tesla.OpenApi.encode_list(unquote(var), fn unquote(item) -> unquote(encode(of, item)) end)
    end
  end

  def encode(%Object{props: props}, var) when props == %{}, do: var

  def encode(%Object{props: props}, var) do
    quote do
      %{unquote_splicing(encode_props(props, var))}
    end
  end

  defp encode_props(props, var) do
    for {name, prop} <- sorted(props) do
      {name, encode(prop, quote(do: unquote(var).unquote(key(name))))}
    end
  end

  ## DECODE

  def decode(%Prim{}, var), do: {:ok, var}
  def decode(%Any{}, var), do: {:ok, var}

  def decode(%Union{of: of}, var) do
    quote do
      cond do
        unquote(Enum.map(of, fn s -> right(match(s, var), decode(s, var)) end))
      end
    end
  end

  def decode(%Ref{name: name, ref: ref}, var) do
    schema = Spec.fetch(ref)

    if moduleless?(schema) do
      decode(schema, var)
    else
      quote(do: unquote(moduleref(name)).decode(unquote(var)))
    end
  end

  def decode(%Array{of: of}, var) do
    item = var("item")

    quote do
      Tesla.OpenApi.decode_list(unquote(var), fn unquote(item) -> unquote(decode(of, item)) end)
    end
  end

  def decode(%Object{props: props}, var) when props === %{}, do: {:ok, var}

  def decode(%Object{props: props}, var) do
    quote do
      with unquote_splicing(decode_props(props, var)) do
        {:ok, %{unquote_splicing(props_map(props))}}
      end
    end
  end

  defp decode_props(props, var) do
    for {name, prop} <- sorted(props) do
      left({:ok, var(name)}, decode(prop, quote(do: unquote(var)[unquote(name)])))
    end
  end

  defp props_map(props) do
    for {name, _prop} <- sorted(props), do: {key(name), var(name)}
  end

  ## MATCH

  def match(%Prim{}, _var), do: true
  def match(%Array{}, var), do: quote(do: is_list(unquote(var)))
  def match(%Object{}, var), do: quote(do: is_map(unquote(var)))
  def match(%Ref{ref: ref}, var), do: match(Spec.fetch(ref), var)

  ## MODEL

  def model(%Model{name: name, schema: %Object{props: props}}) do
    var = var("data")
    types = for {name, prop} <- sorted(props), do: {key(name), type(prop)}
    keys = for {name, _prop} <- sorted(props), do: {key(name), nil}

    quote do
      defmodule unquote(modulename(name)) do
        # @moduledoc unquote(doc_schema(schema))
        defstruct unquote(keys)
        @type t :: %__MODULE__{unquote_splicing(types)}

        def encode(unquote(var)) do
          %{unquote_splicing(encode_props(props, var))}
        end

        def decode(unquote(var)) do
          with unquote_splicing(decode_props(props, var)) do
            {:ok, %__MODULE__{unquote_splicing(props_map(props))}}
          end
        end
      end
    end
  end

  def model(%Model{name: name, schema: schema}) do
    if moduleless?(schema) do
      quote do
        @type unquote(var(name)) :: unquote(type(schema))
      end
    else
      var = var("data")

      quote do
        defmodule unquote(modulename(name)) do
          # @moduledoc unquote(doc_schema(schema))
          @type t :: unquote(type(schema))
          def encode(unquote(var)), do: unquote(encode(schema, var))
          def decode(unquote(var)), do: unquote(decode(schema, var))
        end
      end
    end
  end

  defp moduleless?(%Prim{}), do: true
  defp moduleless?(%Array{of: %Any{}}), do: true
  defp moduleless?(_schema), do: false

  ## OPERATION

  @body Macro.var(:body, __MODULE__)

  def operation(%Operation{id: id, method: method} = op) do
    config = Context.get_config()

    if config.op_gen?(id) do
      name = key(config.op_name(id))
      in_args = in_args(op)
      out_args = out_args(op)

      quote do
        @doc unquote(Doc.operation(op))
        @spec unquote(type(op))

        def unquote(name)(unquote_splicing(in_args)) do
          case Tesla.unquote(key(method))(unquote_splicing(out_args)) do
            unquote(responses(op) ++ catchall())
          end
        end

        defoverridable unquote([{name, length(in_args)}])
      end
    end
  end

  defp in_args(op) do
    flatten_once([
      in_client(),
      in_path_params(op),
      in_body_params(op),
      in_query_params(op)
    ])
  end

  defp in_client, do: quote(do: client \\ new())
  defp in_path_params(%{path_params: params}), do: Enum.map(params, &var(&1.name))
  defp in_body_params(%{request_body: %{}}), do: @body
  defp in_body_params(%{body_params: params}), do: Enum.map(params, &var(&1.name))
  defp in_query_params(%{query_params: []}), do: []
  defp in_query_params(%{query_params: _}), do: quote(do: query \\ [])

  defp out_args(op) do
    flatten_once([
      out_client(),
      out_path(op),
      out_body_params(op),
      out_keyword(op)
    ])
  end

  defp out_client, do: quote(do: client)

  defp out_path(%{path: path}),
    do: Regex.replace(~r/\{([^}]+?)\}/, path, fn _, name -> ":" <> Macro.underscore(name) end)

  defp out_body_params(%{request_body: %{} = schema}), do: encode(schema, @body)
  defp out_body_params(%{body_params: []}), do: []
  defp out_body_params(%{body_params: [%{name: name, schema: s}]}), do: encode(s, var(name))
  defp out_body_params(%{body_params: _params}), do: raise("Not Implemented Yet")

  defp out_keyword(op) do
    wrapped(
      nonempty(
        query: out_query(op),
        opts: out_opts(op)
      )
    )
  end

  defp out_opts(op), do: nonempty(path_params: out_path_params(op))
  defp out_query(%{query_params: []}), do: []

  defp out_query(%{query_params: params}) do
    args = Enum.map(params, &{key(&1.name), nil})

    quote do
      Tesla.OpenApi.encode_query(query, unquote(args))
    end
  end

  defp out_path_params(%{path_params: []}), do: nil

  defp out_path_params(%{path_params: params}),
    do: Enum.map(params, &{key(&1.name), var(&1.name)})

  defp responses(%{responses: responses}) do
    for response <- responses do
      [match] = response(response)
      match
    end
  end

  defp response(%Response{code: :default, schema: nil}) do
    quote do
      {:ok, _} -> :error
    end
  end

  defp response(%Response{code: :default, schema: schema}) do
    quote do
      {:ok, %{body: unquote(@body)}} ->
        with {:ok, data} <- unquote(decode(schema, @body)) do
          {:error, data}
        end
    end
  end

  defp response(%Response{code: code, schema: nil}) when code in 200..299 do
    quote do
      {:ok, %{status: unquote(code)}} -> :ok
    end
  end

  defp response(%Response{code: code, schema: schema}) when code in 200..299 do
    quote do
      {:ok, %{status: unquote(code), body: unquote(@body)}} ->
        unquote(decode(schema, @body))
    end
  end

  defp response(%Response{code: code, schema: nil}) when is_integer(code) do
    quote do
      {:ok, %{status: unquote(code)}} -> {:error, unquote(code)}
    end
  end

  defp response(%Response{code: code, schema: schema}) when is_integer(code) do
    quote do
      {:ok, %{status: unquote(code), body: unquote(@body)}} ->
        with {:ok, data} <- unquote(decode(schema, @body)) do
          {:error, data}
        end
    end
  end

  defp catchall do
    quote do
      {:error, error} -> {:error, error}
    end
  end

  ## NEW

  def new(spec) do
    middleware =
      List.flatten([
        mid_url(spec),
        mid_path(spec),
        mid_encoders(spec),
        mid_decoders(spec)
      ])

    quote do
      @middleware unquote(middleware)

      @spec new() :: Tesla.Client.t()
      def new(), do: new([], nil)

      @spec new([Tesla.Client.middleware()], Tesla.Client.adapter()) :: Tesla.Client.t()
      def new(middleware, adapter) do
        Tesla.client(@middleware ++ middleware, adapter)
      end

      defoverridable new: 0, new: 2
    end
  end

  defp mid_url(spec) do
    scheme = if("https" in spec.schemes, do: "https", else: "http")

    case {spec.host, spec.base_path} do
      {"", ""} -> []
      {"", base} -> {Tesla.Middleware.BaseUrl, base}
      {host, base} -> {Tesla.Middleware.BaseUrl, scheme <> "://" <> host <> base}
    end
  end

  defp mid_path(_spec), do: Tesla.Middleware.PathParams

  defp mid_encoders(spec) do
    Enum.map(spec.consumes, fn
      "application/json" -> Tesla.Middleware.EncodeJson
      _ -> []
    end)
  end

  defp mid_decoders(_spec) do
    [
      Tesla.Middleware.DecodeJson,
      Tesla.Middleware.DecodeFormUrlencoded
    ]
  end

  ## UTILS

  defp key(name), do: name |> Macro.underscore() |> String.replace("/", "_") |> String.to_atom()
  defp var(name), do: Macro.var(key(name), __MODULE__)

  defp modulename(name),
    do: {:__aliases__, [alias: false], [String.to_atom(Macro.camelize(name))]}

  defp moduleref(name), do: Module.concat([moduleref(), Macro.camelize(name)])
  defp moduleref(), do: Context.get_caller()

  defp right(match, body), do: {:->, [], [[match], body]}
  defp left(match, body), do: {:<-, [], [match, body]}

  defp flatten_once(list) do
    Enum.flat_map(list, fn
      x when is_list(x) -> x
      x -> [x]
    end)
  end

  defp nonempty(keyword) do
    Enum.reject(keyword, fn
      {_, nil} -> true
      {_, []} -> true
      _ -> false
    end)
  end

  defp wrapped([]), do: []
  defp wrapped(x), do: [x]

  defp sorted(props), do: Enum.sort_by(props, &elem(&1, 0))
end
