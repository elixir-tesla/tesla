defmodule Tesla.Adapter.Shared do
  @moduledoc false

  def capture_query_params(%Tesla.Env{method: :get, url: url} = env) do
    query_string = URI.parse(url).query

    if query_string do
      query =
        query_string
        |> URI.query_decoder
        |> Enum.to_list
        |> Enum.group_by(fn(x) -> elem(x, 0) end, fn(x) -> elem(x, 1) end)
        |> Enum.map(&decode_pair/1)
        |> Enum.into(%{})

      %{env | query: query}
    else
      env
    end
  end
  def capture_query_params(env), do: env

  defp decode_pair({key, value}) when length(value) === 1, do: {key, value |> Enum.at(0)}
  defp decode_pair({key, value}),                          do: {key, value}

  def stream_to_fun(stream) do
    reductor = fn(item, _acc) -> {:suspend, item} end
    {_, _, fun} = Enumerable.reduce(stream, {:suspend, nil}, reductor)

    fun
  end

  def next_chunk(fun), do: parse_chunk fun.({:cont, nil})

  defp parse_chunk({:suspended, item, fun}), do: {:ok, item, fun}
  defp parse_chunk(_),                       do: :eof
end
