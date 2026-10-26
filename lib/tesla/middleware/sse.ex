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
  - `:reconnect` - when `true` or a keyword list, the body becomes a stream that reconnects
    whenever the connection ends or reading it raises `Tesla.Error`, sending the last event id
    in the `last-event-id` header, as `EventSource` does. Reconnecting stops when the server
    responds with anything other than a `200` event stream, such as a `204`. Defaults to `false`.
    - `:delay` - milliseconds to wait before reconnecting until the server sends a `retry`
      field. Defaults to `3000`.
    - `:max_attempts` - consecutive failed reconnection attempts before giving up. Defaults to
      `:infinity`.
  """

  @behaviour Tesla.Middleware

  @default_content_types ["text/event-stream"]

  @parser %{line: [], cr: false, event: %{}}

  @reconnect_defaults [delay: 3000, max_attempts: :infinity]

  @impl Tesla.Middleware
  def call(env, next, opts) do
    opts = opts || []

    with {:ok, response} <- Tesla.run(env, next) do
      case reconnect_options(opts) do
        nil -> decode(response, opts)
        reconnect -> decode_reconnecting(env, next, response, reconnect, opts)
      end
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
    |> Stream.transform(&start_parsing/0, &parse/2, &finish_parsing/1, &stop_parsing/1)
    |> Stream.flat_map(&only(&1, opts[:only]))
  end

  defp decode_body(binary, opts) when is_binary(binary) do
    {events, parser} = binary |> strip_bom() |> parse(@parser)
    Enum.flat_map(events ++ finish(parser), &only(&1, opts[:only]))
  end

  defp start_parsing, do: @parser

  defp finish_parsing(parser), do: {finish(parser), parser}

  defp stop_parsing(_parser), do: :ok

  defp reconnect_options(opts) do
    case Keyword.get(opts, :reconnect, false) do
      false -> nil
      true -> @reconnect_defaults
      reconnect -> Keyword.merge(@reconnect_defaults, reconnect)
    end
  end

  defp decode_reconnecting(request, next, response, reconnect, opts) do
    case event_stream?(response, opts) do
      true ->
        state = %{
          request: request,
          next: next,
          opts: opts,
          delay: reconnect[:delay],
          max_attempts: reconnect[:max_attempts],
          attempts: 0,
          last_event_id: "",
          body: open_body(response.body),
          parser: @parser
        }

        events =
          Stream.resource(fn -> state end, &next_events/1, &close_body/1)
          |> Stream.flat_map(&only(&1, opts[:only]))

        {:ok, %{response | body: events}}

      false ->
        decode(response, opts)
    end
  end

  defp event_stream?(response, opts) do
    response.status == 200 and decodable_content_type?(response, opts)
  end

  # Unlike a stream that does not reconnect, an event still pending when the connection ends
  # is discarded, as the server sends it again after the last event id.
  defp next_events(%{body: :closed} = state), do: reconnect(state)

  defp next_events(state) do
    case next_chunk(state.body) do
      {:chunk, chunk, body} ->
        parse_chunk(chunk, %{state | body: body})

      :closed ->
        {[], %{state | body: :closed, parser: @parser}}
    end
  end

  defp parse_chunk(chunk, state) do
    {events, parser} = parse(chunk, state.parser)
    {events, %{track(state, events) | parser: parser}}
  end

  defp reconnect(%{attempts: attempts, max_attempts: attempts} = state), do: {:halt, state}

  defp reconnect(state) do
    Process.sleep(state.delay)

    case Tesla.run(last_event_id_request(state), state.next) do
      {:ok, response} ->
        case event_stream?(response, state.opts) do
          true -> {[], %{state | body: open_body(response.body), attempts: 0}}
          false -> {:halt, state}
        end

      {:error, _reason} ->
        {[], %{state | attempts: state.attempts + 1}}
    end
  end

  defp last_event_id_request(%{request: request, last_event_id: ""}) do
    Tesla.delete_header(request, "last-event-id")
  end

  defp last_event_id_request(%{request: request, last_event_id: last_event_id}) do
    Tesla.put_header(request, "last-event-id", last_event_id)
  end

  defp track(state, events), do: Enum.reduce(events, state, &track_event/2)

  defp track_event(event, state) do
    state = Map.update!(state, :last_event_id, &Map.get(event, :id, &1))

    case event do
      %{retry: retry} -> %{state | delay: String.to_integer(retry)}
      _ -> state
    end
  end

  defp open_body(body) when is_binary(body), do: open_body([body])

  defp open_body(body) do
    body = strip_stream_bom(body)
    &Enumerable.reduce(body, &1, fn chunk, _acc -> {:suspend, chunk} end)
  end

  defp next_chunk(body) do
    case body.({:cont, nil}) do
      {:suspended, chunk, body} -> {:chunk, chunk, body}
      {_done_or_halted, _acc} -> :closed
    end
  rescue
    Tesla.Error -> :closed
  end

  defp close_body(%{body: :closed}), do: :ok
  defp close_body(%{body: body}), do: body.({:halt, nil})

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
  # same line ending at the start of the next chunk.
  defp parse("", parser), do: {[], parser}
  defp parse("\n" <> chunk, %{cr: true} = parser), do: parse(chunk, %{parser | cr: false})

  defp parse(chunk, parser) do
    parser = %{parser | cr: ends_with_cr?(chunk)}

    case :binary.split(chunk, ["\r\n", "\n", "\r"], [:global]) do
      [partial] ->
        {[], %{parser | line: [parser.line, partial]}}

      [first | rest] ->
        parse_lines(first, rest, parser)
    end
  end

  defp parse_lines(first, rest, parser) do
    first = IO.iodata_to_binary([parser.line, first])
    {lines, [partial]} = Enum.split([first | rest], -1)

    {events, event} =
      lines
      |> Enum.map(&replace_invalid_utf8/1)
      |> Enum.flat_map_reduce(parser.event, &parse_line/2)

    {events, %{parser | line: [partial], event: event}}
  end

  # Unlike the spec, an event still pending when the body ends is returned, as it was before.
  defp finish(%{line: line, event: event}) do
    case IO.iodata_to_binary(line) do
      "" -> dispatch(event)
      line -> finish_line(line, event)
    end
  end

  defp finish_line(line, event) do
    {[], event} = line |> replace_invalid_utf8() |> parse_line(event)
    dispatch(event)
  end

  defp ends_with_cr?(chunk) do
    :binary.last(chunk) == ?\r
  end

  defp parse_line("", event), do: {dispatch(event), %{}}

  defp parse_line(line, event) do
    case decode_body(line) do
      :empty -> {[], event}
      {:data, data} -> {[], Map.update(event, :data, data, &(&1 <> "\n" <> data))}
      {:comment, comment} -> {[], Map.put_new(event, :comment, comment)}
      {key, value} -> {[], Map.put(event, key, value)}
    end
  end

  # Each maximal ill-formed subsequence becomes one U+FFFD, as the UTF-8 decoder does.
  # https://encoding.spec.whatwg.org/#utf-8-decoder
  defp replace_invalid_utf8(line) do
    case String.valid?(line) do
      true -> line
      false -> replace_invalid_utf8(line, [])
    end
  end

  defp replace_invalid_utf8(<<>>, acc) do
    acc |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp replace_invalid_utf8(<<char::utf8, rest::binary>>, acc) do
    replace_invalid_utf8(rest, [<<char::utf8>> | acc])
  end

  defp replace_invalid_utf8(<<lead, rest::binary>>, acc) do
    size = continuation_size(rest, continuation_ranges(lead))
    {_invalid, rest} = :erlang.split_binary(rest, size)

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

  # Unlike the spec, blocks without data, such as one with only a comment, an id or a retry,
  # are returned as they were before, so callers can still track id and retry updates.
  defp dispatch(event) when map_size(event) == 0, do: []
  defp dispatch(event), do: [event]

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
      "id" -> decode_id(value)
      "retry" -> decode_retry(value)
      _ -> :empty
    end
  end

  defp decode_id(value) do
    case String.contains?(value, <<0>>) do
      true -> :empty
      false -> {:id, value}
    end
  end

  defp decode_retry(value) do
    case ascii_digits?(value) do
      true -> {:retry, value}
      false -> :empty
    end
  end

  defp ascii_digits?(value), do: value =~ ~r/\A[0-9]+\z/

  defp strip_leading_space(" " <> value), do: value
  defp strip_leading_space(value), do: value

  defp decodable_content_type?(env, opts) do
    case Tesla.get_header(env, "content-type") do
      nil -> false
      content_type -> matches_content_type?(content_type, content_types(opts))
    end
  end

  defp matches_content_type?(content_type, content_types) do
    content_type = String.downcase(content_type)
    Enum.any?(content_types, &String.starts_with?(content_type, &1))
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
