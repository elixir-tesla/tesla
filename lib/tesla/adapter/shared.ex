defmodule Tesla.Adapter.Shared do
  @moduledoc false

  def stream_to_fun(stream) do
    reductor = fn item, _acc -> {:suspend, item} end
    {_, _, fun} = Enumerable.reduce(stream, {:suspend, nil}, reductor)

    fun
  end

  def next_chunk(fun), do: parse_chunk(fun.({:cont, nil}))

  defp parse_chunk({:suspended, item, fun}), do: {:ok, item, fun}
  defp parse_chunk(_), do: :eof
end
