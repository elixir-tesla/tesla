defmodule TestSupport do
  def gzip_headers(env) do
    env.headers
    |> Enum.map_join("|", fn {key, value} -> "#{key}: #{value}" end)
    |> :zlib.gzip()
  end
end
