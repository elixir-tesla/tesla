defmodule Tesla.OpenApi.Doc do
  def module(info) do
    version =
      case info.version do
        nil -> nil
        vsn -> "Version: #{vsn}"
      end

    merge([
      info.title,
      info.description,
      version
    ])
  end

  # def schema(schema) do
  # merge([
  #   schema.title,
  #   schema.description
  # ])
  # end

  def operation(op) do
    query_params =
      for %{name: name, description: desc} <- op.query_params do
        case desc do
          nil -> "- `#{name}`"
          desc -> "- `#{name}`: #{desc}"
        end
      end

    query_docs =
      case query_params do
        [] ->
          nil

        qs ->
          """
          ### Query parameters

          #{Enum.join(qs, "\n")}
          """
      end

    external_docs =
      case op.external_docs do
        %{description: description, url: url} -> "[#{description}](#{url})"
        _ -> nil
      end

    merge([
      op.summary,
      op.description,
      query_docs,
      external_docs
    ])
  end

  defp merge(parts) do
    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end
end
