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
    |> Stream.transform(new_parser(), &parse/2)
    |> Stream.flat_map(&only(&1, opts[:only]))
  end

  defp decode_body(binary, opts) when is_binary(binary) do
    {events, _parser} = binary |> strip_bom() |> parse(new_parser())
    Enum.flat_map(events, &only(&1, opts[:only]))
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

  # A line can end with CRLF, so a CR at the end of a chunk may be followed by the LF of the
  # same line ending at the start of the next chunk. An event that is still pending when the
  # body ends is discarded.
  defp new_parser(), do: %{line: [], cr: false, event: %{}}

  defp parse("", parser), do: {[], parser}
  defp parse("\n" <> chunk, %{cr: true} = parser), do: parse(chunk, %{parser | cr: false})

  defp parse(chunk, parser) do
    parser = %{parser | cr: :binary.last(chunk) == ?\r}

    case :binary.split(chunk, ["\r\n", "\n", "\r"], [:global]) do
      [partial] ->
        {[], %{parser | line: [parser.line, partial]}}

      [first | rest] ->
        {lines, [partial]} = Enum.split([IO.iodata_to_binary([parser.line, first]) | rest], -1)
        {events, event} = Enum.flat_map_reduce(lines, parser.event, &parse_line/2)
        {events, %{parser | line: [partial], event: event}}
    end
  end

  defp parse_line("", event), do: {dispatch(event), %{}}

  defp parse_line(line, event) do
    case line |> replace_invalid_utf8() |> decode_body() do
      :empty -> {[], event}
      {:data, data} -> {[], Map.update(event, :data, data, &(&1 <> "\n" <> data))}
      {:comment, comment} -> {[], Map.put_new(event, :comment, comment)}
      {key, value} -> {[], Map.put(event, key, value)}
    end
  end

  # Each maximal ill-formed subsequence becomes one U+FFFD, as the UTF-8 decoder does.
  # https://encoding.spec.whatwg.org/#utf-8-decoder
  defp replace_invalid_utf8(line) do
    if String.valid?(line), do: line, else: replace_invalid_utf8(line, [])
  end

  defp replace_invalid_utf8(<<>>, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp replace_invalid_utf8(<<char::utf8, rest::binary>>, acc),
    do: replace_invalid_utf8(rest, [<<char::utf8>> | acc])

  defp replace_invalid_utf8(<<lead, rest::binary>>, acc) do
    size = continuation_size(rest, continuation_ranges(lead))
    <<_::binary-size(size), rest::binary>> = rest
    replace_invalid_utf8(rest, ["\uFFFD" | acc])
  end

  defp continuation_ranges(lead) when lead in 0xC2..0xDF, do: [{0x80, 0xBF}]
  defp continuation_ranges(0xE0), do: [{0xA0, 0xBF}, {0x80, 0xBF}]
  defp continuation_ranges(0xED), do: [{0x80, 0x9F}, {0x80, 0xBF}]
  defp continuation_ranges(lead) when lead in 0xE1..0xEF, do: [{0x80, 0xBF}, {0x80, 0xBF}]
  defp continuation_ranges(0xF0), do: [{0x90, 0xBF}, {0x80, 0xBF}, {0x80, 0xBF}]
  defp continuation_ranges(0xF4), do: [{0x80, 0x8F}, {0x80, 0xBF}, {0x80, 0xBF}]

  defp continuation_ranges(lead) when lead in 0xF1..0xF3,
    do: [{0x80, 0xBF}, {0x80, 0xBF}, {0x80, 0xBF}]

  defp continuation_ranges(_lead), do: []

  defp continuation_size(<<byte, rest::binary>>, [{first, last} | ranges])
       when byte >= first and byte <= last,
       do: 1 + continuation_size(rest, ranges)

  defp continuation_size(_rest, _ranges), do: 0

  # Comments are kept as events, although the spec ignores them.
  defp dispatch(%{data: _} = event), do: [event]
  defp dispatch(%{comment: _} = event), do: [event]
  defp dispatch(_event), do: []

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
      content_type -> media_type(content_type) in Enum.map(content_types(opts), &media_type/1)
    end
  end

  # Media types are case-insensitive and may be followed by parameters.
  # https://www.rfc-editor.org/rfc/rfc9110#section-8.3.1
  defp media_type(content_type) do
    [media_type | _parameters] = String.split(content_type, ";", parts: 2)
    media_type |> String.trim() |> String.downcase()
  end

  defp content_types(opts),
    do: @default_content_types ++ Keyword.get(opts, :decode_content_types, [])

  defp only(message, nil), do: [message]

  defp only(message, key) do
    case Map.get(message, key) do
      nil -> []
      val -> [val]
    end
  end
end
