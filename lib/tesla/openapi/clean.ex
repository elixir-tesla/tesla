defmodule Tesla.OpenApi.Clean do
  def clean(code), do: Macro.postwalk(code, &c/1)

  # Match `cond do; true -> x; end`
  # and replace with `x`
  defp c({:cond, _, [[do: [{:->, [], [[true], var]}]]]}) do
    var
  end

  # Match cond with multiple clauses and make sure they are unique
  defp c({:cond, ctx, [[do: clauses]]}) when length(clauses) >= 2 do
    # Combine clauses with the same result into one joined with `or`
    clauses
    |> Enum.reduce(%{}, fn
      {:->, _, [[con], out]}, acc -> Map.update(acc, out, [con], fn xs -> [con | xs] end)
    end)
    |> Enum.map(fn {out, conds} ->
      con =
        Enum.reduce(conds, fn
          # if one of the clauses is `true` replace all of them with `true`
          _, true -> true
          a, b -> {:or, [], [a, b]}
        end)

      {:->, [], [[con], out]}
    end)
    |> Enum.uniq()
    |> case do
      [one] ->
        c({:cond, ctx, [[do: [one]]]})

      many ->
        # Make sure the clauses with `true` condition is last
        {trues, others} =
          Enum.split_with(many, fn
            {:->, [], [[true], _]} -> true
            _ -> false
          end)

        {:cond, ctx, [[do: others ++ trues]]}
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

  # Replace `with {:ok, x} <- {:ok, y}, do: {:ok/:error, x}`
  # with    `{:ok/:error, x}`
  defp c({:with, _, [{:<-, _, [ok: var, ok: rhs]}, [do: {ok, var}]]}) do
    {ok, rhs}
  end

  # Remove unnecessary always-matching clauses like `{:ok, x} <- {:ok, y}`
  # Remove `with` once all clauses are removed
  defp c({:with, _, clauses} = ast) do
    [[do: body] | matches] = Enum.reverse(clauses)

    case body do
      # {:ok, %__MODULE__{id: id, name: name, ... }}
      {:ok, {:%, sctx, [{:__MODULE__, _, _} = struct, {:%{}, _, _} = map]}} ->
        case clean_with(map, matches) do
          {:ok, map} -> {:ok, {:%, sctx, [struct, map]}}
          other -> other
        end

      # {:ok, %{id: id, name: name, ... }}
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
