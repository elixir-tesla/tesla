defmodule Tesla.OpenApi3.Gen do
  alias Tesla.OpenApi3.{Prim, Union, Array, Object, Ref, Any}
  alias Tesla.OpenApi3.Model
  alias Tesla.OpenApi3.Spec

  ## TYPES

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
      var(name)
    else
      quote(do: unquote(moduleref(name)).t())
    end
  end

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

  def encode(%Object{props: props}, var) do
    quote do
      %{unquote_splicing(encode_props(props, var))}
    end
  end

  defp encode_props(props, var) do
    for {name, prop} <- props do
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

  def decode(%Object{props: props}, var) do
    quote do
      with unquote_splicing(decode_props(props, var)) do
        {:ok, %{unquote_splicing(props_map(props))}}
      end
    end
  end

  defp decode_props(props, var) do
    for {name, prop} <- props do
      left({:ok, var(name)}, decode(prop, quote(do: unquote(var)[unquote(name)])))
    end
  end

  defp props_map(props) do
    for {name, _prop} <- props, do: {key(name), var(name)}
  end

  ## MATCH

  def match(%Prim{}, _var), do: true
  def match(%Array{}, var), do: quote(do: is_list(unquote(var)))
  def match(%Object{}, var), do: quote(do: is_map(unquote(var)))

  ## MODEL

  def model(%Model{name: name, schema: %Object{props: props}}) do
    var = var("data")
    types = for {name, prop} <- props, do: {key(name), type(prop)}
    keys = for {name, _prop} <- props, do: {key(name), nil}

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

  ## UTILS

  defp key(name), do: name |> Macro.underscore() |> String.replace("/", "_") |> String.to_atom()
  defp var(name), do: Macro.var(key(name), __MODULE__)

  defp modulename(name),
    do: {:__aliases__, [alias: false], [String.to_atom(Macro.camelize(name))]}

  defp moduleref(name), do: Module.concat([moduleref(), Macro.camelize(name)])
  defp moduleref(), do: :erlang.get(:__tesla__caller)

  defp right(match, body), do: {:->, [], [[match], body]}
  defp left(match, body), do: {:<-, [], [match, body]}
end
