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

  @spec prepare_path(String.t() | nil, String.t() | nil) :: String.t()
  def prepare_path(nil, nil), do: "/"
  def prepare_path(nil, query), do: "/?" <> query
  def prepare_path(path, nil), do: path
  def prepare_path(path, query), do: path <> "?" <> query

  @spec format_method(atom()) :: String.t()
  def format_method(method), do: to_string(method) |> String.upcase()
end
