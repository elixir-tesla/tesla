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
  - `:reconnect` - `false`, `nil` or leaving it out disables reconnecting. Otherwise it takes
    `true` or a keyword list, where `true` is the same as `[]` and uses the defaults, and the
    body becomes a stream that reconnects whenever the connection ends or reading it raises
    `Tesla.Error`, sending the last event id in the `last-event-id` header, as `EventSource`
    does. A `last-event-id` header on the request seeds that id, and the id the server sends
    replaces it. The stream raises `Tesla.Error` when it gives up, so a consumer can tell an outage
    or an expired token from a completed stream. A `204` response to a reconnection is the one
    clean end, as the server asked to stop. Any other response that is not a `200` event stream
    raises with `reason` `:unexpected_response` and `env` set to that response. The body of
    either response is closed first. Reaching `:max_attempts` raises with `env` set to the last
    request and `reason` `{:max_attempts, last_reason}`, where `last_reason` is the error of the
    last failed request, the `Tesla.Error` raised while reading the last body, or `:closed` when
    the last connection ended without an event. Any other value, and any key other than the following, raises an
    `ArgumentError` before the request runs. Only `GET` requests reconnect, any other method is
    decoded as without `:reconnect`, so a client wide `reconnect: []` is safe for its other
    calls. `EventSource` only issues `GET` requests, and replaying a body would send the work
    again. See the
    [processing model](https://html.spec.whatwg.org/multipage/server-sent-events.html#sse-processing-model)
    in the WHATWG spec. The Finch, Mint and Gun adapters raise `Tesla.Error` when a streamed
    body fails, so reconnecting needs one of them or an adapter that does the same. A read
    timeout, reason `:timeout` or `:recv_chunk_timeout`, is not a dropped connection and is
    raised to the consumer without reconnecting. `EventSource` has no read timeout, so set the
    adapter's receive timeout above the server's heartbeat interval, or to `:infinity`.
    - `:delay` - non-negative integer of milliseconds to wait before reconnecting until the
      server sends a `retry` field. Defaults to `3000`, the value Chrome picked, since the WHATWG spec leaves the
      initial reconnection time to each implementation.
    - `:max_delay` - non-negative integer of milliseconds that caps the `retry` field the
      server sends, so a huge value cannot park the consumer. Defaults to `60000`. `:delay` must not
      exceed it.
    - `:max_attempts` - positive integer, or `:infinity`, of consecutive reconnection
      attempts before giving up. A reconnection counts as an attempt until an event arrives on it,
      so a connection that is established but closes without sending an event is counted too.
      Defaults to `:infinity`, since the WHATWG spec never gives up reestablishing a connection.

  A `retry` field applies as soon as it is read, even when the connection closes before the blank
  line that would dispatch its block.
  """

  @behaviour Tesla.Middleware

  @default_content_types ["text/event-stream"]

  @parser %{line: [], cr: false, event: %{}}

  @reconnect_defaults [delay: 3000, max_delay: 60_000, max_attempts: :infinity]

  @impl Tesla.Middleware
  def call(env, next, opts) do
    opts = opts || []

    reconnect = reconnect_opts!(opts)

    with {:ok, response} <- Tesla.run(env, next) do
      decode_response(env, next, response, opts, reconnect)
    end
  end

  defp decode_response(%Tesla.Env{method: :get} = request, next, response, opts, reconnect)
       when reconnect != nil do
    decode_reconnecting(request, next, response, opts, reconnect)
  end

  defp decode_response(_request, _next, response, opts, _reconnect), do: decode(response, opts)

  defp reconnect_opts!(opts) do
    case Keyword.get(opts, :reconnect) do
      value when value in [nil, false] -> nil
      true -> @reconnect_defaults
      value -> merge_reconnect!(value)
    end
  end

  defp merge_reconnect!(value) do
    case Keyword.keyword?(value) do
      true -> value |> reject_unknown_reconnect_keys!() |> validate_reconnect!()
      false -> invalid_reconnect(value)
    end
  end

  defp reject_unknown_reconnect_keys!(value) do
    case Keyword.keys(value) -- Keyword.keys(@reconnect_defaults) do
      [] ->
        value

      [unknown | _] ->
        raise ArgumentError,
              "unknown :reconnect option #{inspect(unknown)}, expected one of " <>
                inspect(Keyword.keys(@reconnect_defaults))
    end
  end

  defp validate_reconnect!(value) do
    reconnect = Keyword.merge(@reconnect_defaults, value)
    validate_delay!(reconnect[:delay])
    validate_max_delay!(reconnect[:max_delay])
    validate_delay_within_max!(reconnect[:delay], reconnect[:max_delay])
    validate_max_attempts!(reconnect[:max_attempts])
    reconnect
  end

  defp validate_delay!(delay) when is_integer(delay) and delay >= 0, do: :ok

  defp validate_delay!(delay) do
    raise ArgumentError, "expected :delay to be an integer >= 0, got #{inspect(delay)}"
  end

  defp validate_max_delay!(max_delay) when is_integer(max_delay) and max_delay >= 0, do: :ok

  defp validate_max_delay!(max_delay) do
    raise ArgumentError, "expected :max_delay to be an integer >= 0, got #{inspect(max_delay)}"
  end

  defp validate_delay_within_max!(delay, max_delay) when delay <= max_delay, do: :ok

  defp validate_delay_within_max!(delay, max_delay) do
    raise ArgumentError, "expected :delay #{delay} not to exceed :max_delay #{max_delay}"
  end

  defp validate_max_attempts!(:infinity), do: :ok
  defp validate_max_attempts!(attempts) when is_integer(attempts) and attempts >= 1, do: :ok

  defp validate_max_attempts!(attempts) do
    raise ArgumentError,
          "expected :max_attempts to be an integer >= 1 or :infinity, got #{inspect(attempts)}"
  end

  defp invalid_reconnect(value) do
    raise ArgumentError,
          "expected :reconnect to be a boolean, nil or a keyword list, got #{inspect(value)}"
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

  defp decode_reconnecting(request, next, response, opts, reconnect) do
    case event_stream?(response, opts) do
      true ->
        start = start_reconnecting(request, next, response, opts, reconnect)

        events =
          Stream.resource(start, &next_events/1, &close_body/1)
          |> Stream.flat_map(&only(&1, opts[:only]))

        {:ok, %{response | body: events}}

      false ->
        decode(response, opts)
    end
  end

  defp start_reconnecting(request, next, response, opts, reconnect) do
    fn ->
      %{
        request: request,
        next: next,
        opts: opts,
        delay: reconnect[:delay],
        max_delay: reconnect[:max_delay],
        max_attempts: reconnect[:max_attempts],
        attempts: 0,
        last_reason: :closed,
        last_event_id: seeded_event_id(request),
        body: open_body(response.body),
        parser: @parser,
        pending_error: nil
      }
    end
  end

  defp event_stream?(response, opts) do
    response.status == 200 and decodable_content_type?(response, opts)
  end

  # Unlike a stream that does not reconnect, an event still pending when the connection ends
  # is discarded, as the server sends it again after the last event id.
  defp next_events(%{pending_error: {kind, reason, stacktrace}}),
    do: :erlang.raise(kind, reason, stacktrace)

  defp next_events(%{body: :closed} = state), do: reconnect(state)

  defp next_events(state) do
    case next_chunk(state.body) do
      {:chunk, chunk, body} ->
        parse_chunk(chunk, %{state | body: body})

      :closed ->
        {[], %{state | body: :closed, parser: @parser}}

      {:closed, error} ->
        {[], %{state | body: :closed, parser: @parser, last_reason: error}}

      {:raised, kind, reason, stacktrace} ->
        {[], %{state | body: :closed, pending_error: {kind, reason, stacktrace}}}
    end
  end

  defp parse_chunk(chunk, state) do
    {events, parser} = parse(chunk, state.parser)
    state = %{state | parser: parser} |> track(events) |> apply_pending_retry()
    {events, state}
  end

  defp apply_pending_retry(%{parser: %{event: %{retry: retry}}} = state) do
    %{state | delay: clamp_retry(retry, state.max_delay)}
  end

  defp apply_pending_retry(state), do: state

  defp reconnect(%{attempts: attempts, max_attempts: attempts} = state) do
    raise Tesla.Error,
      env: last_event_id_request(state),
      reason: {:max_attempts, state.last_reason}
  end

  defp reconnect(state) do
    Process.sleep(state.delay)

    case Tesla.run(last_event_id_request(state), state.next) do
      {:ok, response} -> resume(response, state)
      {:error, reason} -> {[], %{state | attempts: state.attempts + 1, last_reason: reason}}
    end
  end

  defp resume(response, state) do
    case event_stream?(response, state.opts) do
      true ->
        {[],
         %{
           state
           | body: open_body(response.body),
             attempts: state.attempts + 1,
             last_reason: :closed
         }}

      false ->
        release_body(response.body)
        end_or_raise(response, state)
    end
  end

  defp release_body(nil), do: :ok
  defp release_body(body), do: close_body(%{body: open_body(body)})

  defp end_or_raise(%{status: 204}, state), do: {:halt, state}

  defp end_or_raise(response, _state) do
    raise Tesla.Error, env: response, reason: :unexpected_response
  end

  defp seeded_event_id(request) do
    case last_event_id_headers(request) do
      [{_name, last_event_id} | _] -> last_event_id
      [] -> ""
    end
  end

  defp last_event_id_request(%{request: request, last_event_id: last_event_id}) do
    request = drop_last_event_id(request)

    case last_event_id do
      "" -> request
      last_event_id -> Tesla.put_header(request, "last-event-id", last_event_id)
    end
  end

  defp drop_last_event_id(request) do
    %{request | headers: Enum.reject(request.headers, &last_event_id_header?/1)}
  end

  defp last_event_id_headers(request), do: Enum.filter(request.headers, &last_event_id_header?/1)

  defp last_event_id_header?({name, _value}),
    do: String.downcase(to_string(name)) == "last-event-id"

  defp track(state, events), do: Enum.reduce(events, state, &track_event/2)

  defp track_event(event, state) do
    state = %{state | attempts: 0}
    state = Map.update!(state, :last_event_id, &Map.get(event, :id, &1))

    case event do
      %{retry: retry} -> %{state | delay: clamp_retry(retry, state.max_delay)}
      _ -> state
    end
  end

  defp clamp_retry(retry, max_delay) do
    retry = String.trim_leading(retry, "0")

    case byte_size(retry) > length(Integer.digits(max_delay)) do
      true -> max_delay
      false -> retry |> to_milliseconds() |> min(max_delay)
    end
  end

  defp to_milliseconds(""), do: 0
  defp to_milliseconds(digits), do: String.to_integer(digits)

  defp open_body(body) when is_binary(body), do: open_body([body])

  defp open_body(body) do
    body = strip_stream_bom(body)
    fn acc -> Enumerable.reduce(body, acc, &suspend/2) end
  end

  defp suspend(chunk, _acc), do: {:suspend, chunk}

  defp next_chunk(body) do
    case body.({:cont, nil}) do
      {:suspended, chunk, body} -> {:chunk, chunk, body}
      {_done_or_halted, _acc} -> :closed
    end
  catch
    kind, reason -> closed_or_raised(kind, reason, __STACKTRACE__)
  end

  defp closed_or_raised(:error, %Tesla.Error{reason: reason} = error, stacktrace)
       when reason in [:timeout, :recv_chunk_timeout],
       do: {:raised, :error, error, stacktrace}

  defp closed_or_raised(:error, %Tesla.Error{} = error, _stacktrace), do: {:closed, error}

  defp closed_or_raised(kind, reason, stacktrace), do: {:raised, kind, reason, stacktrace}

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
