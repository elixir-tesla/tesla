defmodule Tesla.OpenApi3.Spec do
  alias Tesla.OpenApi3.{Prim, Union, Array, Object, Ref, Any}
  alias Tesla.OpenApi3.Model

  defstruct spec: %{}, models: %{}, operations: %{}
  @type t :: %__MODULE__{spec: map(), models: map(), operations: map()}

  @spec from(map) :: Tesla.OpenApi3.schema()

  # Prim
  # TODO: Collapse null type into required/optional fields
  def from(%{"type" => "null"}), do: %Prim{type: :null}
  def from(%{"type" => "string"}), do: %Prim{type: :binary}
  def from(%{"type" => "integer"}), do: %Prim{type: :integer}
  def from(%{"type" => "number"}), do: %Prim{type: :number}
  def from(%{"type" => "boolean"}), do: %Prim{type: :boolean}

  # Union
  def from(%{"type" => types}) when is_list(types),
    do: collapse(%Union{of: Enum.map(types, &from(%{"type" => &1}))})

  def from(%{"items" => items}) when is_list(items),
    do: collapse(%Union{of: Enum.map(items, &from/1)})

  def from(%{"anyOf" => anyof}),
    do: collapse(%Union{of: Enum.map(anyof, &from/1)})

  # Array
  def from(%{"type" => "array", "items" => items}), do: %Array{of: from(items)}
  def from(%{"type" => "array"}), do: %Array{of: %Any{}}
  def from(%{"items" => %{} = items}), do: %Array{of: from(items)}

  # Object
  def from(%{"properties" => %{} = props}),
    do: %Object{
      props:
        props
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.into(%{}, fn {key, val} -> {key, from(val)} end)
    }

  def from(%{"type" => "object", "allOf" => allof}), do: %Object{props: merge_props(allof)}
  def from(%{"type" => "object"}), do: %Object{props: %{}}

  # Ref
  # v2
  def from(%{"$ref" => "#/definitions/" <> name = ref}), do: %Ref{name: name, ref: ref}
  # v3
  def from(%{"$ref" => "#/components/schemas/" <> name = ref}), do: %Ref{name: name, ref: ref}
  def from(%{"$ref" => ref}), do: fetch(ref)

  # Any
  def from(map) when map === %{}, do: %Any{}

  # Found in Slack spec
  def from(%{"additionalProperties" => false}), do: %Any{}

  def fetch(ref), do: from(dereference(ref))

  defp merge_props(schemas) do
    Enum.reduce(schemas, %{}, fn schema, acc ->
      props =
        case from(schema) do
          %Object{props: props} -> props
          %Ref{ref: ref} -> dereference(ref)
        end

      Map.merge(acc, props)
    end)
  end

  defp collapse(%Union{of: of}) do
    %Union{of: List.flatten(collapse(of))}
  end

  defp collapse(schemas) when is_list(schemas) do
    schemas
    |> Enum.reduce([[], [], []], fn
      %Object{} = x, [os, as, ps] -> [collapse(x, os), as, ps]
      # %Object{} = x, [[], as, ps] -> [[x], as, ps]
      # %Object{} = x, [[y], as, ps] -> [[collapse(x, y)], as, ps]

      %Array{} = x, [os, as, ps] -> [os, collapse(x, as), ps]
      # %Array{} = x, [os, [], ps] -> [os, [x], ps]
      # %Array{} = x, [os, [y], ps] -> [os, [collapse(x, y)], ps]

      %Prim{} = x, [os, as, ps] -> [os, as, collapse(x, ps)]
      %Union{} = x, [os, as, ps] -> collapse(x, [os, as, ps])
    end)
  end

  defp collapse(%Object{} = x, [%Object{} = y]) do
    props = Map.merge(x.props, y.props, fn _k, a, b -> collapse(%Union{of: [a, b]}) end)
    [%Object{props: props}]
  end

  defp collapse(%Array{of: x}, [%Array{of: y}]) do
    [%Array{of: collapse(%Union{of: [x, y]})}]
  end

  defp collapse(%Prim{} = x, prims) do
    Enum.uniq(prims ++ [x])
  end

  defp collapse(%Union{of: of}, [yos, yas, yps]) do
    [xos, xas, xps] = collapse(of)
    [collapse(xos, yos), collapse(xas, yas), collapse(xps, yps)]
  end

  defp collapse([x], ys) do
    collapse(x, ys)
  end

  defp collapse(xs, ys) when is_list(xs) and is_list(ys) do
    xs ++ ys
  end

  defp collapse(x, []) do
    [x]
  end

  defp dereference(ref) do
    spec = :erlang.get(:__tesla__spec)

    if spec == :undefined do
      raise "Spec not found under :__tesla__spec key"
    end

    case get_in(spec, compile_path(ref)) do
      nil -> raise "Reference #{ref} not found"
      item -> item
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
      :get, data, next when is_list(data) -> data |> Enum.at(String.to_integer(key)) |> next.()
      :get, data, next when is_map(data) -> data |> Map.get(key) |> next.()
    end
  end

  defp key_or_index(key), do: key

  @spec read(binary) :: t()
  def read(file) do
    spec = file |> File.read!() |> Jason.decode!()

    load(spec)

    %__MODULE__{
      spec: spec,
      models: models(spec)
    }
  end

  def load(spec), do: :erlang.put(:__tesla__spec, spec)

  # 2.x
  defp models(%{"definitions" => defs}), do: models(defs)
  # 3.x
  defp models(%{"components" => %{"schemas" => defs}}), do: models(defs)

  defp models(defs) when is_list(defs) or is_map(defs) do
    for {name, schema} <- defs, do: %Model{name: name, schema: from(schema)}
  end
end
