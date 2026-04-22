defmodule TestSupport do
  def custom_query_encoder(query), do: URI.encode_query(query)

  def gzip_headers(env) do
    env.headers
    |> Enum.map_join("|", fn {key, value} -> "#{key}: #{value}" end)
    |> :zlib.gzip()
  end
end
