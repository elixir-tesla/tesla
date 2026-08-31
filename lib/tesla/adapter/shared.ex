defmodule Tesla.Adapter.Shared do
  @moduledoc false

  def stream_to_fun(stream) do
    {_, _, fun} = Enumerable.reduce(stream, {:suspend, :start}, &suspend_chunk/2)

    fun
  end

  defp suspend_chunk(item, _acc), do: {:suspend, {:chunk, item}}

  def next_chunk(fun), do: parse_chunk(fun.({:cont, :start}))

  defp parse_chunk({:suspended, {:chunk, item}, fun}), do: {:ok, item, fun}
  defp parse_chunk({:halted, {:chunk, item}}), do: {:ok, item, &no_chunk/1}
  defp parse_chunk(_), do: :eof

  defp no_chunk({_command, acc}), do: {:done, acc}

  @spec prepare_path(String.t() | nil, String.t() | nil) :: String.t()
  def prepare_path(nil, nil), do: "/"
  def prepare_path(nil, query), do: "/?" <> query
  def prepare_path(path, nil), do: path
  def prepare_path(path, query), do: path <> "?" <> query

  @spec format_method(atom()) :: String.t()
  def format_method(method), do: to_string(method) |> String.upcase()
end
