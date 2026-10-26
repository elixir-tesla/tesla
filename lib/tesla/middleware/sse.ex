defmodule Tesla.Middleware.SSE do
  @moduledoc """
  Decode Server Sent Events.

  This middleware is mostly useful when streaming response body.

  ## Examples

  ```elixir
  defmodule MyClient do
    def client do
      Tesla.client([Tesla.Middleware.SSE, only: :data])
    end
  end
  ```

  ## Options

  - `:only` - keep only specified keys in event (necessary for using with `JSON` middleware)
  - `:decode_content_types` - list of additional decodable content-types
  """

  @behaviour Tesla.Middleware

  @default_content_types ["text/event-stream"]

  @impl Tesla.Middleware
  def call(env, next, opts) do
    opts = opts || []

    with {:ok, env} <- Tesla.run(env, next) do
      decode(env, opts)
    end
  end

  def decode(env, opts) do
    if decodable_content_type?(env, opts) do
      {:ok, %{env | body: decode_body(env.body, opts)}}
    else
      {:ok, env}
    end
  end

  defp decode_body(body, opts) when is_struct(body, Stream) or is_function(body) do
    body
    |> strip_stream_bom()
    |> Stream.chunk_while(
      "",
      fn elem, acc ->
        {lines, [rest]} =
          (acc <> elem)
          |> String.split(double_linebreak_regex())
          |> Enum.split(-1)

        {:cont, lines, rest}
      end,
      fn
        "" -> {:cont, ""}
        acc -> {:cont, [acc], ""}
      end
    )
    |> Stream.flat_map(& &1)
    |> Stream.map(&decode_message/1)
    |> Stream.flat_map(&only(&1, opts[:only]))
  end

  defp decode_body(binary, opts) when is_binary(binary) do
    binary
    |> strip_bom()
    |> String.split(double_linebreak_regex())
    |> Enum.map(&decode_message/1)
    |> Enum.flat_map(&only(&1, opts[:only]))
  end

  # A byte order mark at the very start of the stream is not part of the first line, but one
  # anywhere else is. In a stream it can be split across chunks, so up to two bytes that may be
  # its start are held back until the next chunk arrives.
  @bom <<0xEF, 0xBB, 0xBF>>

  defp strip_bom(@bom <> rest), do: rest
  defp strip_bom(binary), do: binary

  defp strip_stream_bom(stream) do
    Stream.transform(
      stream,
      fn -> "" end,
      fn
        chunk, :done -> {[chunk], :done}
        chunk, start -> strip_start_bom(start <> chunk)
      end,
      fn
        :done -> {[], :done}
        start -> {[start], :done}
      end,
      fn _acc -> :ok end
    )
  end

  defp strip_start_bom(@bom <> rest), do: {[rest], :done}

  defp strip_start_bom(start) when byte_size(start) < byte_size(@bom) do
    if binary_part(@bom, 0, byte_size(start)) == start, do: {[], start}, else: {[start], :done}
  end

  defp strip_start_bom(start), do: {[start], :done}

  defp double_linebreak_regex(), do: ~r/((\r\n)|((?<!\r)\n)|(\r(?!\n))){2}/

  defp decode_message(message) do
    message
    |> String.split(["\r\n", "\n", "\r"])
    |> Enum.map(&decode_body/1)
    |> Enum.reduce(%{}, fn
      :empty, acc -> acc
      {:data, data}, acc -> Map.update(acc, :data, data, &(&1 <> "\n" <> data))
      {:comment, comment}, acc -> Map.put_new(acc, :comment, comment)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp decode_body(""), do: :empty
  defp decode_body(":" <> comment), do: {:comment, strip_leading_space(comment)}

  # The field name is everything before the first colon, and one space after the
  # colon is not part of the value. A line without a colon is a field with an
  # empty value. Unknown fields are ignored.
  # https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation
  defp decode_body(line) do
    {field, value} =
      case :binary.split(line, ":") do
        [field, value] -> {field, strip_leading_space(value)}
        [field] -> {field, ""}
      end

    case field do
      "data" -> {:data, value}
      "event" -> {:event, value}
      "id" -> if String.contains?(value, <<0>>), do: :empty, else: {:id, value}
      "retry" -> if ascii_digits?(value), do: {:retry, value}, else: :empty
      _ -> :empty
    end
  end

  defp ascii_digits?(value), do: value =~ ~r/\A[0-9]+\z/

  defp strip_leading_space(" " <> value), do: value
  defp strip_leading_space(value), do: value

  defp decodable_content_type?(env, opts) do
    case Tesla.get_header(env, "content-type") do
      nil -> false
      content_type -> Enum.any?(content_types(opts), &String.starts_with?(content_type, &1))
    end
  end

  defp content_types(opts),
    do: @default_content_types ++ Keyword.get(opts, :decode_content_types, [])

  # A message without any known field, such as one with only an unknown field, is not an event.
  defp only(message, _key) when map_size(message) == 0, do: []
  defp only(message, nil), do: [message]

  defp only(message, key) do
    case Map.get(message, key) do
      nil -> []
      val -> [val]
    end
  end
end
