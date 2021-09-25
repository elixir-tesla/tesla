defmodule Tesla.OpenApi3.Clean do
  def clean(code), do: Macro.postwalk(code, &c/1)

  # Match `cond do; true -> x; end`
  # and replace with `x`
  defp c({:cond, _, [[do: [{:->, [], [[true], var]}]]]}) do
    var
  end

  # Match cond with multiple clauses and make sure they are unique
  defp c({:cond, ctx, [[do: clauses]]}) when length(clauses) >= 2 do
    case Enum.uniq(clauses) do
      [one] -> c({:cond, ctx, [[do: [one]]]})
      many -> {:cond, ctx, [[do: many]]}
    end
  end

  # Match `Tesla.OpenApi.decode_list(var, fn data -> {:ok, data} end)`
  # and replace with `{:ok, var}`
  defp c({{:., _, [_, :decode_list]}, [], [var, {:fn, _, [{:->, _, [[data], {:ok, data}]}]}]}) do
    {:ok, var}
  end

  # Match `Tesla.OpenApi.encode_list(var, fn data -> data end)`
  # and replace with `{:ok, var}`
  defp c({{:., _, [_, :encode_list]}, [], [var, {:fn, _, [{:->, _, [[data], data]}]}]}) do
    var
  end

  # Remove unnecessary always-matching clauses like `{:ok, x} <- {:ok, y}`
  # Remove `with` once all clauses are removed
  defp c({:with, _, clauses} = ast) do
    [[do: body] | matches] = Enum.reverse(clauses)

    case body do
      # %__MODULE__{id: id, name: name, ... }
      {:ok, {:%, sctx, [{:__MODULE__, _, _} = struct, {:%{}, _, _} = map]}} ->
        case clean_with(map, matches) do
          {:ok, map} -> {:ok, {:%, sctx, [struct, map]}}
          other -> other
        end

      # %{id: id, name: name, ... }
      {:ok, {:%{}, _, _} = map} ->
        clean_with(map, matches)

      _ ->
        ast
    end

    # TODO: Make assigns unique
    # TODO: Remove pointless assigns {:error, _} <- {:ok, data["key"]}
  end

  defp c(code), do: code

  defp clean_with({:%{}, _, assigns}, matches) do
    {matches, replacements} =
      Enum.reduce(matches, {[], %{}}, fn
        {:<-, _, [ok: lhs, ok: rhs]}, {mat, rep} -> {mat, Map.put(rep, lhs, rhs)}
        other, {mat, rep} -> {[other | mat], rep}
      end)

    assigns = Enum.map(assigns, fn {key, var} -> {key, Map.get(replacements, var) || var} end)
    body = {:ok, {:%{}, [], assigns}}

    case matches do
      [] -> body
      _ -> {:with, [], Enum.reverse([[do: body] | matches])}
    end
  end
end
