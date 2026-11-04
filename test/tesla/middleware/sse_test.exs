defmodule Tesla.Middleware.SSETest do
  use ExUnit.Case

  @env %Tesla.Env{
    status: 200,
    headers: [{"content-type", "text/event-stream"}]
  }

  describe "Basics" do
    test "ignore not matching content-type" do
      adapter = fn _env ->
        {:ok, %Tesla.Env{headers: [{"content-type", "text/plain"}], body: "test"}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == "test"
    end

    test "decode comment" do
      adapter = fn _env ->
        {:ok, %{@env | body: ": comment"}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{comment: "comment"}]
    end

    test "decode multiple messages" do
      body = """
      : this is a test stream

      data: some text

      data: another message
      data: with two lines
      """

      adapter = fn _env ->
        {:ok, %{@env | body: body}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])

      assert env.body == [
               %{comment: "this is a test stream"},
               %{data: "some text"},
               %{data: "another message\nwith two lines"}
             ]
    end

    test "decode named events" do
      body = """
      event: userconnect
      data: {"username": "bobby", "time": "02:33:48"}

      data: Here's a system message of some kind that will get used
      data: to accomplish some task.

      event: usermessage
      data: {"username": "bobby", "time": "02:34:11", "text": "Hi everyone."}
      """

      adapter = fn _env ->
        {:ok, %{@env | body: body}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])

      assert env.body == [
               %{event: "userconnect", data: ~s|{"username": "bobby", "time": "02:33:48"}|},
               %{
                 data:
                   "Here's a system message of some kind that will get used\nto accomplish some task."
               },
               %{
                 event: "usermessage",
                 data: ~s|{"username": "bobby", "time": "02:34:11", "text": "Hi everyone."}|
               }
             ]
    end

    test "decode fields without a space after the colon, without a value and unknown fields" do
      body = """
      data:hello
      event:greeting

      data

      data:
      id:

      foo: bar
      data : x
      data: y

      :comment
      """

      adapter = fn _env ->
        {:ok, %{@env | body: body}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])

      assert env.body == [
               %{data: "hello", event: "greeting"},
               %{data: ""},
               %{data: "", id: ""},
               %{data: "y"},
               %{comment: "comment"}
             ]
    end

    test "ignore an event with only an unknown field" do
      adapter = fn _env ->
        {:ok, %{@env | body: "foo: bar\n\ndata: x\n\n"}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "x"}]
    end

    test "strip a leading byte order mark" do
      adapter = fn _env ->
        {:ok, %{@env | body: "\uFEFFdata: first\n\ndata: second\n\n"}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "first"}, %{data: "second"}]
    end

    test "output only data" do
      body = """
      : comment1

      event: userconnect
      data: data1

      data: data2
      data: data3

      event: usermessage
      data: data4
      """

      adapter = fn _env ->
        {:ok, %{@env | body: body}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], only: :data)

      assert env.body == ["data1", "data2\ndata3", "data4"]
    end
  end

  describe "streaming response" do
    test "handle stream data" do
      adapter = fn _env ->
        chunks = [
          ~s|dat|,
          ~s|a: dat|,
          ~s|a1\n\ndata: data2\n\ndata: d|,
          ~s|ata3\n\n|
        ]

        stream = Stream.map(chunks, & &1)

        {:ok, %{@env | body: stream}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])

      assert Enum.to_list(env.body) == [%{data: "data1"}, %{data: "data2"}, %{data: "data3"}]
    end

    test "handle stream data with fields without a space after the colon" do
      adapter = fn _env ->
        chunks = [
          ~s|data:hel|,
          ~s|lo\nevent:gr|,
          ~s|eeting\n\nfoo: bar\n\nda|,
          ~s|ta\n\n|
        ]

        {:ok, %{@env | body: Stream.map(chunks, & &1)}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])

      assert Enum.to_list(env.body) == [%{data: "hello", event: "greeting"}, %{data: ""}]
    end

    test "handle stream data with a leading byte order mark split across chunks" do
      adapter = fn _env ->
        chunks = [<<0xEF>>, <<0xBB>>, <<0xBF>> <> "data: first\n\n", "data: \uFEFFsecond\n\n"]
        {:ok, %{@env | body: Stream.map(chunks, & &1)}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])

      # only the byte order mark at the start of the stream is removed
      assert Enum.to_list(env.body) == [%{data: "first"}, %{data: "\uFEFFsecond"}]
    end

    test "decode the same events wherever the stream is split after a leading byte order mark" do
      body = "\uFEFFdata: hello\n\n"

      for split <- 0..byte_size(body) do
        {first, second} = :erlang.split_binary(body, split)

        adapter = fn _env ->
          {:ok, %{@env | body: Stream.map([first, second], & &1)}}
        end

        assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
        assert Enum.to_list(env.body) == [%{data: "hello"}], "split at byte #{split}"
      end
    end

    test "handle an empty stream" do
      adapter = fn _env ->
        {:ok, %{@env | body: Stream.map([], & &1)}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert Enum.to_list(env.body) == []
    end

    test "handle stream data with varying line terminators" do
      adapter = fn _env ->
        chunks = [
          ~s|data: data1\n|,
          ~s|\ndata: data2\r|,
          ~s|\r\ndata: data3\r\revent: event4\r|,
          ~s|\ndata: data4\n\n|
        ]

        stream = Stream.map(chunks, & &1)

        {:ok, %{@env | body: stream}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])

      assert Enum.to_list(env.body) == [
               %{data: "data1"},
               %{data: "data2"},
               %{data: "data3"},
               %{event: "event4", data: "data4"}
             ]
    end

    test "handle unterminated final message" do
      adapter = fn _env ->
        chunks = [
          ~s|data: data1\n\n|,
          ~s|data: data2\n\n|,
          ~s|data: data3|
        ]

        stream = Stream.map(chunks, & &1)

        {:ok, %{@env | body: stream}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])

      assert Enum.to_list(env.body) == [%{data: "data1"}, %{data: "data2"}, %{data: "data3"}]
    end
  end

  describe "fields without a dedicated test" do
    test "decode id and retry" do
      body = """
      id: 42

      retry: 3000
      """

      adapter = fn _env -> {:ok, %{@env | body: body}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{id: "42"}, %{retry: "3000"}]
    end

    test "ignore response without a content-type" do
      adapter = fn _env -> {:ok, %Tesla.Env{headers: [], body: "test"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == "test"
    end
  end

  describe "event stream interpretation" do
    # https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation

    test "the last event field wins" do
      adapter = fn _env -> {:ok, %{@env | body: "event: a\nevent: b\ndata: x\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{event: "b", data: "x"}]
    end

    test "the last id field wins" do
      adapter = fn _env -> {:ok, %{@env | body: "id: 1\nid: 2\ndata: x\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{id: "2", data: "x"}]
    end

    test "ignore an id field containing a null character" do
      adapter = fn _env -> {:ok, %{@env | body: "id: a\0b\ndata: x\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "x"}]
    end

    test "ignore a retry field that is not only ASCII digits" do
      adapter = fn _env ->
        {:ok, %{@env | body: "retry: abc\ndata: x\n\nretry:\ndata: y\n\nretry: 1.5\ndata: z\n\n"}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "x"}, %{data: "y"}, %{data: "z"}]
    end

    test "remove only one space after the colon" do
      adapter = fn _env -> {:ok, %{@env | body: "data:  x\nevent:\tb\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: " x", event: "\tb"}]
    end

    test "split the field from the value at the first colon only" do
      adapter = fn _env -> {:ok, %{@env | body: "data: a:b: c\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "a:b: c"}]
    end

    test "join data fields with a line feed, keeping empty ones" do
      adapter = fn _env -> {:ok, %{@env | body: "data: a\ndata:\ndata: b\n\ndata\ndata\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "a\n\nb"}, %{data: "\n"}]
    end

    test "treat a field name without a colon as a field with an empty value" do
      adapter = fn _env -> {:ok, %{@env | body: "id\nevent\ndata\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{id: "", event: "", data: ""}]
    end

    test "ignore a retry field with a space before the digits" do
      adapter = fn _env -> {:ok, %{@env | body: "retry:  10\ndata: x\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "x"}]
    end

    test "decode a retry field with only ASCII digits" do
      adapter = fn _env -> {:ok, %{@env | body: "retry: 3000\ndata: x\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{retry: "3000", data: "x"}]
    end

    test "treat field names with leading whitespace as unknown fields" do
      adapter = fn _env -> {:ok, %{@env | body: " data: a\n\tdata: b\ndata: c\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "c"}]
    end

    test "a line with only whitespace is not a blank line" do
      adapter = fn _env -> {:ok, %{@env | body: "data: a\n \ndata: b\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "a\nb"}]
    end

    test "consecutive and leading blank lines do not produce events" do
      adapter = fn _env -> {:ok, %{@env | body: "\n\n\ndata: a\n\n\n\n\ndata: b\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "a"}, %{data: "b"}]
    end

    test "decode a body that only uses carriage returns" do
      adapter = fn _env -> {:ok, %{@env | body: "data: a\rdata: b\r\rdata: c\r\r"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "a\nb"}, %{data: "c"}]
    end

    test "decode a body that mixes line terminators" do
      adapter = fn _env ->
        {:ok, %{@env | body: "data: a\r\ndata: b\rdata: c\n\r\ndata: d\r\n\r"}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "a\nb\nc"}, %{data: "d"}]
    end

    test "strip only one leading byte order mark" do
      adapter = fn _env -> {:ok, %{@env | body: "\uFEFF\uFEFFdata: a\n\ndata: b\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "b"}]
    end

    test "replace invalid UTF-8 with the replacement character" do
      adapter = fn _env -> {:ok, %{@env | body: <<"data: a", 0xFF, "b\n\n">>}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "a\uFFFDb"}]
    end

    # https://encoding.spec.whatwg.org/#utf-8-decoder
    test "replace each maximal ill-formed UTF-8 subsequence with one replacement character" do
      adapter = fn _env ->
        {:ok,
         %{
           @env
           | body:
               <<"data: ", 0xE2, 0x82, "|", 0xF0, 0x9F, 0x91, "|", 0xC0, 0x80, "|", 0xED, 0xA0,
                 0x80, "\n\n">>
         }}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "\uFFFD|\uFFFD|\uFFFD\uFFFD|\uFFFD\uFFFD\uFFFD"}]
    end

    test "replace ill-formed UTF-8 that starts with a lead byte that restricts its second byte" do
      adapter = fn _env ->
        {:ok,
         %{
           @env
           | body:
               <<"data: ", 0xE0, 0xA0, "|", 0xE0, 0x80, "|", 0xF4, 0x8F, 0xBF, "|", 0xF4, 0x90,
                 "|", 0xF2, 0x80, 0x80, "\n\n">>
         }}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "\uFFFD|\uFFFD\uFFFD|\uFFFD|\uFFFD\uFFFD|\uFFFD"}]
    end

    test "replace invalid UTF-8 with the replacement character in a stream" do
      adapter = fn _env ->
        {:ok, %{@env | body: Stream.map([<<"data: a", 0xC3>>, "b\n\n"], & &1)}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert Enum.to_list(env.body) == [%{data: "a\uFFFDb"}]
    end

    test "decode a UTF-8 character split across chunks" do
      adapter = fn _env ->
        {:ok, %{@env | body: Stream.map(["data: caf", <<0xC3>>, <<0xA9>>, "\n\n"], & &1)}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert Enum.to_list(env.body) == [%{data: "café"}]
    end

    test "treat CRLF split across chunks as one line terminator" do
      adapter = fn _env ->
        {:ok, %{@env | body: Stream.map(["data: a\r", "\ndata: b\r", "\n\r", "\n"], & &1)}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert Enum.to_list(env.body) == [%{data: "a\nb"}]
    end

    test "treat a blank CRLF line split across chunks as one blank line" do
      adapter = fn _env ->
        {:ok, %{@env | body: Stream.map(["data: a\r\n\r", "\ndata: b\r\n\r", "\n"], & &1)}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert Enum.to_list(env.body) == [%{data: "a"}, %{data: "b"}]
    end

    test "decode a stream delivered one byte at a time" do
      body = "\uFEFFdata:a\r\nid: 1\revent: e\n\r\n: c\ndata: \u00E9\n\n"

      adapter = fn _env ->
        {:ok, %{@env | body: Stream.map(:binary.bin_to_list(body), &<<&1>>)}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])

      assert Enum.to_list(env.body) == [
               %{data: "a", id: "1", event: "e"},
               %{comment: "c", data: "é"}
             ]
    end

    test "the last valid retry field wins" do
      adapter = fn _env ->
        {:ok,
         %{
           @env
           | body: "retry: 1000\nretry: 2000\ndata: x\n\nretry: 1000\nretry: 10ms\ndata: y\n\n"
         }}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{retry: "2000", data: "x"}, %{retry: "1000", data: "y"}]
    end

    test "ignore a retry field with a sign or non-ASCII digits" do
      adapter = fn _env ->
        {:ok, %{@env | body: "retry: -1\nretry: +1\nretry: ١\ndata: x\n\n"}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "x"}]
    end

    test "an id field containing a null character keeps the previous id" do
      adapter = fn _env ->
        {:ok, %{@env | body: "id: 1\nid: a\0b\ndata: x\n\nid: \0\ndata: y\n\n"}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{id: "1", data: "x"}, %{data: "y"}]
    end

    test "ignore unknown fields without a value" do
      adapter = fn _env -> {:ok, %{@env | body: "unknown\n\nevent: e\nunknown\ndata: x\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{event: "e", data: "x"}]
    end

    test "a comment containing a field is still a comment" do
      adapter = fn _env -> {:ok, %{@env | body: ":data: x\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{comment: "data: x"}]
    end

    test "a comment inside an event does not split its data" do
      adapter = fn _env -> {:ok, %{@env | body: "data: a\n: c\ndata: b\n\n"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{comment: "c", data: "a\nb"}]
    end

    test "preserve multi-byte UTF-8 in every field" do
      adapter = fn _env ->
        {:ok, %{@env | body: "id: 事件-☃\nevent: résumé\ndata: café こんにちは 👋\n\n"}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{id: "事件-☃", event: "résumé", data: "café こんにちは 👋"}]
    end

    test "decode a four byte character and a grapheme split across chunks" do
      <<e1, e2, e3, e4>> = "👋"

      adapter = fn _env ->
        chunks = ["data: ", <<e1, e2>>, <<e3, e4, "cafe", 0xCC>>, <<0x81, "\n\n">>]
        {:ok, %{@env | body: Stream.map(chunks, & &1)}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert Enum.to_list(env.body) == [%{data: "👋café"}]
    end

    test "remove one space after the colon when it arrives in its own chunk" do
      adapter = fn _env ->
        chunks = ["event:", " ", "a\ndata:", " ", " b\n\n"]
        {:ok, %{@env | body: Stream.map(chunks, & &1)}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert Enum.to_list(env.body) == [%{event: "a", data: " b"}]
    end

    test "a stream of only blank lines produces no events" do
      adapter = fn _env ->
        {:ok, %{@env | body: Stream.map(["", "\n", "\r\n", "\r", ""], & &1)}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert Enum.to_list(env.body) == []
    end

    test "dispatch an event as soon as its blank line arrives" do
      adapter = fn _env ->
        chunks =
          Stream.resource(
            fn -> ["data: a\n\n", "data: b\r\r", :halt] end,
            fn
              [:halt] -> raise "the next chunk was read before the event was dispatched"
              [chunk | rest] -> {[chunk], rest}
            end,
            fn _ -> :ok end
          )

        {:ok, %{@env | body: chunks}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert Enum.take(env.body, 2) == [%{data: "a"}, %{data: "b"}]
    end

    test "decode a long data line split into many chunks" do
      line = String.duplicate("x", 256 * 1024)
      body = "data: " <> line <> "\n\n"

      adapter = fn _env ->
        chunks =
          Stream.unfold(body, fn
            "" -> nil
            rest -> String.split_at(rest, 1024)
          end)

        {:ok, %{@env | body: chunks}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert Enum.to_list(env.body) == [%{data: line}]
    end
  end

  describe "content type" do
    test "decode a content type with parameters" do
      adapter = fn _env ->
        {:ok,
         %{
           @env
           | headers: [{"content-type", "text/event-stream; charset=utf-8"}],
             body: "data: x\n\n"
         }}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "x"}]
    end

    # https://www.rfc-editor.org/rfc/rfc9110#section-8.3.1
    test "match the content type case-insensitively" do
      adapter = fn _env ->
        {:ok, %{@env | headers: [{"content-type", "Text/Event-Stream"}], body: "data: x\n\n"}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "x"}]
    end
  end

  describe "only option" do
    test "keep only data from events that are dispatched" do
      adapter = fn _env ->
        {:ok,
         %{@env | body: ": c\n\nevent: e\n\nid: 1\n\nfoo: bar\n\nevent: e\ndata: x\n\ndata\n\n"}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], only: :data)
      assert env.body == ["x", ""]
    end
  end

  describe "backwards compatibility" do
    test "return blocks with only an id, a retry or an event" do
      adapter = fn _env ->
        {:ok, %{@env | body: "id: 1\n\nretry: 10\n\nevent: a\n\ndata: x\n\n"}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{id: "1"}, %{retry: "10"}, %{event: "a"}, %{data: "x"}]
    end

    test "return blocks with only an id, a retry or an event in a stream" do
      adapter = fn _env ->
        chunks = ["id: 1\n\nre", "try: 10\n\nevent: a\n", "\ndata: x\n\n"]
        {:ok, %{@env | body: Stream.map(chunks, & &1)}}
      end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert Enum.to_list(env.body) == [%{id: "1"}, %{retry: "10"}, %{event: "a"}, %{data: "x"}]
    end

    test "return an unterminated final event" do
      adapter = fn _env -> {:ok, %{@env | body: "data: a\n\nid: 1\ndata: b"}} end

      assert {:ok, env} = Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}], [])
      assert env.body == [%{data: "a"}, %{id: "1", data: "b"}]
    end

    test "decode a content type that starts with a decodable content type" do
      adapter = fn _env ->
        {:ok,
         %{@env | headers: [{"content-type", "application/x-events-v2"}], body: "data: x\n\n"}}
      end

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{}, [{:fn, adapter}],
                 decode_content_types: ["application/x-events"]
               )

      assert env.body == [%{data: "x"}]
    end
  end

  describe "body without reconnect" do
    test "is an eager list that can be enumerated twice" do
      adapter = fn _env -> {:ok, %{@env | body: "data: a\n\ndata: b\n\n"}} end

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}], [])

      assert is_list(env.body)
      assert Enum.take(env.body, 1) == [%{data: "a"}]
      assert Enum.to_list(env.body) == [%{data: "a"}, %{data: "b"}]
    end
  end

  describe "reconnect option" do
    test "do not reconnect a request that is not a GET" do
      first = {:ok, %{@env | body: "id: 1\ndata: a\n\n"}}
      second = {:ok, %{@env | body: "data: b\n\n"}}
      request = %Tesla.Env{method: :post, body: "payload"}

      assert {:ok, plain} =
               Tesla.Middleware.SSE.call(request, [{:fn, sequence_adapter([first])}], [])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(
                 request,
                 [{:fn, sequence_adapter([first, second])}],
                 reconnect: [delay: 0]
               )

      assert Enum.to_list(env.body) == [%{id: "1", data: "a"}]
      assert Enum.to_list(env.body) == Enum.to_list(plain.body)

      assert_received {:request, _plain}
      assert_received {:request, _first}
      refute_received {:request, _second}
    end

    test "reconnect when the stream ends and send the last event id" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: Stream.map(["id: 1\ndata: a\n\n"], & &1)}},
          {:ok, %{@env | body: Stream.map(["data: b\n\n"], & &1)}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      assert Enum.to_list(env.body) == [%{id: "1", data: "a"}, %{data: "b"}]

      assert_received {:request, first}
      assert Tesla.get_header(first, "last-event-id") == nil
      assert_received {:request, second}
      assert Tesla.get_header(second, "last-event-id") == "1"
      assert_received {:request, third}
      assert Tesla.get_header(third, "last-event-id") == "1"
    end

    test "stop sending the last event id once the server clears it" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "id: 1\ndata: a\n\nid\ndata: b\n\n"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      assert Enum.to_list(env.body) == [%{id: "1", data: "a"}, %{id: "", data: "b"}]

      assert_received {:request, _first}
      assert_received {:request, second}
      assert Tesla.get_header(second, "last-event-id") == nil
    end

    for name <- ["Last-Event-ID", "last-event-id"] do
      test "keep the id the caller seeded as #{name} when the connection drops before any event id" do
        adapter =
          sequence_adapter([
            {:ok, %{@env | body: ": comment\n\n"}},
            {:ok, %Tesla.Env{status: 204}}
          ])

        request = %Tesla.Env{method: :get, headers: [{unquote(name), "42"}]}

        assert {:ok, env} =
                 Tesla.Middleware.SSE.call(request, [{:fn, adapter}], reconnect: [delay: 0])

        assert Enum.to_list(env.body) == [%{comment: "comment"}]

        assert_received {:request, _first}
        assert_received {:request, second}
        assert [{_name, "42"}] = last_event_id_headers(second)
      end
    end

    test "reconnect a request whose headers use atom keys" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "id: 7\ndata: a\n\n"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      request = %Tesla.Env{method: :get, headers: [{:accept, "text/event-stream"}]}

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(request, [{:fn, adapter}], reconnect: [delay: 0])

      assert Enum.to_list(env.body) == [%{id: "7", data: "a"}]

      assert_received {:request, _first}
      assert_received {:request, second}
      assert {:accept, "text/event-stream"} in second.headers
      assert Tesla.get_header(second, "last-event-id") == "7"
    end

    test "replace a seeded last event id with the one the server sends" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "id: 7\ndata: a\n\n"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      request = %Tesla.Env{method: :get, headers: [{"Last-Event-ID", "42"}]}

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(request, [{:fn, adapter}], reconnect: [delay: 0])

      assert Enum.to_list(env.body) == [%{id: "7", data: "a"}]

      assert_received {:request, _first}
      assert_received {:request, second}
      assert [{_name, "7"}] = last_event_id_headers(second)
    end

    test "send no last event id once the server clears a seeded one" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "id\ndata: a\n\n"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      request = %Tesla.Env{method: :get, headers: [{"Last-Event-ID", "42"}]}

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(request, [{:fn, adapter}], reconnect: [delay: 0])

      assert Enum.to_list(env.body) == [%{id: "", data: "a"}]

      assert_received {:request, _first}
      assert_received {:request, second}
      assert last_event_id_headers(second) == []
    end

    test "send the id of an earlier event when a later event in the same chunk has none" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "id: 1\ndata: a\n\ndata: b\n\n"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      assert Enum.to_list(env.body) == [%{id: "1", data: "a"}, %{data: "b"}]

      assert_received {:request, _first}
      assert_received {:request, second}
      assert Tesla.get_header(second, "last-event-id") == "1"
    end

    test "wait for the reconnection time sent by the server" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "retry: 50\ndata: a\n\n"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 5000]
               )

      {elapsed, events} = :timer.tc(fn -> Enum.to_list(env.body) end, :millisecond)

      assert events == [%{retry: "50", data: "a"}]
      assert elapsed >= 50
      assert elapsed < 1000
    end

    test "prefer a trailing retry field over an earlier one in the same chunk" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "retry: 1000\ndata: a\n\nretry: 0\n"}},
          {:ok, %{@env | body: "data: b\n\n"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 400]
               )

      {elapsed, events} = :timer.tc(fn -> Enum.to_list(env.body) end, :millisecond)

      assert events == [%{retry: "1000", data: "a"}, %{data: "b"}]
      assert elapsed < 200
    end

    test "apply a retry field when the stream ends before its blank line" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "data: a\n\nretry: 0\n"}},
          {:ok, %{@env | body: "data: b\n\n"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 400]
               )

      {elapsed, events} = :timer.tc(fn -> Enum.to_list(env.body) end, :millisecond)

      assert events == [%{data: "a"}, %{data: "b"}]
      assert elapsed < 200
    end

    test "apply a retry field split across chunks when the stream ends before its blank line" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: Stream.map(["data: a\n\nret", "ry: 0\n"], & &1)}},
          {:ok, %{@env | body: "data: b\n\n"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 400]
               )

      {elapsed, events} = :timer.tc(fn -> Enum.to_list(env.body) end, :millisecond)

      assert events == [%{data: "a"}, %{data: "b"}]
      assert elapsed < 200
    end

    test "do not send a pending id as the last event id when the stream ends" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "id: 1\ndata: a\n\nid: 9"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      assert Enum.to_list(env.body) == [%{id: "1", data: "a"}]

      assert_received {:request, _first}
      assert_received {:request, second}
      assert Tesla.get_header(second, "last-event-id") == "1"
    end

    test "raise when the server rejects a reconnection" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "data: a\n\n"}},
          {:ok, %Tesla.Env{status: 503, headers: [{"content-type", "text/plain"}], body: "down"}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      error = assert_raise Tesla.Error, fn -> Enum.to_list(env.body) end
      assert error.reason == :unexpected_response
      assert error.env.status == 503
      assert Tesla.get_header(error.env, "content-type") == "text/plain"
    end

    test "raise when the server responds to a reconnection with another status" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "data: a\n\n"}},
          {:ok, %{@env | status: 500, body: "data: b\n\n"}},
          {:ok, %{@env | body: "data: c\n\n"}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      error = assert_raise Tesla.Error, fn -> Enum.to_list(env.body) end
      assert error.reason == :unexpected_response
      assert error.env.status == 500
    end

    test "raise when the server responds to a reconnection with another content type" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "data: a\n\n"}},
          {:ok, %Tesla.Env{status: 200, headers: [{"content-type", "text/plain"}], body: "b"}},
          {:ok, %{@env | body: "data: c\n\n"}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      error = assert_raise Tesla.Error, fn -> Enum.to_list(env.body) end
      assert error.reason == :unexpected_response
      assert error.env.body == "b"
    end

    test "clamp a server retry too long to convert to an integer" do
      digits = String.duplicate("9", 2_000_000)

      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "retry: #{digits}\ndata: a\n\n"}},
          {:ok, %{@env | body: "data: b\n\n"}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0, max_delay: 10]
               )

      {elapsed, events} = :timer.tc(fn -> env.body |> Enum.take(2) end, :millisecond)

      assert Enum.map(events, & &1.data) == ["a", "b"]
      assert elapsed < 1000
    end

    test "clamp the server retry to the maximum delay" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "retry: 4294967296\ndata: a\n\n"}},
          {:ok, %{@env | body: "data: b\n\n"}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0, max_delay: 10]
               )

      {elapsed, events} = :timer.tc(fn -> env.body |> Enum.take(2) end, :millisecond)

      assert Enum.map(events, & &1.data) == ["a", "b"]
      assert elapsed < 1000
    end

    test "reconnect at once on a server retry of only zeros" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "retry: 000\ndata: a\n\n"}},
          {:ok, %{@env | body: "data: b\n\n"}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 400]
               )

      {elapsed, events} = :timer.tc(fn -> env.body |> Enum.take(2) end, :millisecond)

      assert Enum.map(events, & &1.data) == ["a", "b"]
      assert elapsed < 200
    end

    test "end the stream when the server responds to a reconnection with 204" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "data: a\n\n"}},
          {:ok, %Tesla.Env{status: 204}},
          {:ok, %{@env | body: "data: c\n\n"}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      assert Enum.to_list(env.body) == [%{data: "a"}]
    end

    test "close the body of a 204 response to a reconnection" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "data: a\n\n"}},
          {:ok, %Tesla.Env{status: 204, body: observed_body()}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      assert Enum.to_list(env.body) == [%{data: "a"}]
      assert_received :rejected_body_closed
      assert_received :rejected_body_opened
      refute_received :rejected_body_opened
      refute_received :chunk_read
    end

    test "close the body of an unexpected response to a reconnection" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "data: a\n\n"}},
          {:ok,
           %Tesla.Env{
             status: 503,
             headers: [{"content-type", "text/plain"}],
             body: observed_body()
           }}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      assert_raise Tesla.Error, fn -> Enum.to_list(env.body) end
      assert_received :rejected_body_closed
      assert_received :rejected_body_opened
      refute_received :rejected_body_opened
      refute_received :chunk_read
    end

    test "give up after the maximum number of failed reconnection attempts" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "data: a\n\n"}},
          {:error, :econnrefused},
          {:error, :econnrefused},
          {:ok, %{@env | body: "data: b\n\n"}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0, max_attempts: 2]
               )

      error = assert_raise Tesla.Error, fn -> Enum.to_list(env.body) end
      assert error.reason == {:max_attempts, :econnrefused}
      assert error.env.method == :get
    end

    test "count failed reconnection attempts only until a connection succeeds" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "data: a\n\n"}},
          {:error, :econnrefused},
          {:ok, %{@env | body: "data: b\n\n"}},
          {:error, :econnrefused},
          {:ok, %{@env | body: "data: c\n\n"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0, max_attempts: 2]
               )

      assert Enum.to_list(env.body) == [%{data: "a"}, %{data: "b"}, %{data: "c"}]
    end

    test "count a reconnection that yields no event as a failed attempt" do
      adapter =
        repeating_adapter(
          [{:ok, %{@env | body: "data: a\n\n"}}],
          {:ok, %{@env | body: ""}}
        )

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0, max_attempts: 2]
               )

      error = assert_raise Tesla.Error, fn -> Enum.to_list(env.body) end
      assert error.reason == {:max_attempts, :closed}
      assert requests() == 3
    end

    test "reset the failed attempts when an event arrives on a reconnection" do
      adapter =
        repeating_adapter(
          [
            {:ok, %{@env | body: "data: a\n\n"}},
            {:ok, %{@env | body: ""}},
            {:ok, %{@env | body: "data: b\n\n"}}
          ],
          {:ok, %{@env | body: ""}}
        )

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0, max_attempts: 2]
               )

      error = assert_raise Tesla.Error, fn -> Enum.to_list(env.body) end
      assert error.reason == {:max_attempts, :closed}
      assert requests() == 5
    end

    test "carry the error of the last dropped body when the attempts run out" do
      dropping_body =
        Stream.map([:econnreset], &raise(Tesla.Error, env: %Tesla.Env{}, reason: &1))

      adapter =
        repeating_adapter(
          [{:ok, %{@env | body: Stream.concat(["data: a\n\n"], dropping_body)}}],
          {:ok, %{@env | body: dropping_body}}
        )

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0, max_attempts: 2]
               )

      error = assert_raise Tesla.Error, fn -> Enum.to_list(env.body) end
      assert {:max_attempts, %Tesla.Error{reason: :econnreset}} = error.reason
      assert requests() == 3
    end

    test "reconnect when reading the body fails and discard the unfinished event" do
      failing_body =
        Stream.concat(
          ["data: a\n\ndata: unfinished"],
          Stream.map([:closed], &raise(Tesla.Error, env: %Tesla.Env{}, reason: &1))
        )

      adapter =
        sequence_adapter([
          {:ok, %{@env | body: failing_body}},
          {:ok, %{@env | body: Stream.map(["data: b\n\n"], & &1)}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      assert Enum.to_list(env.body) == [%{data: "a"}, %{data: "b"}]
    end

    test "raise instead of reconnecting when reading the body times out with :timeout" do
      timing_out_body =
        Stream.concat(
          ["data: a\n\n"],
          Stream.map([:timeout], &raise(Tesla.Error, env: %Tesla.Env{}, reason: &1))
        )

      adapter =
        sequence_adapter([
          {:ok, %{@env | body: timing_out_body}},
          {:ok, %{@env | body: Stream.map(["data: b\n\n"], & &1)}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      error = assert_raise Tesla.Error, fn -> Enum.to_list(env.body) end
      assert error.reason == :timeout
      assert_received {:request, _}
      refute_received {:request, _}
    end

    test "raise instead of reconnecting when reading the body times out with :recv_chunk_timeout" do
      timing_out_body =
        Stream.concat(
          ["data: a\n\n"],
          Stream.map([:recv_chunk_timeout], &raise(Tesla.Error, env: %Tesla.Env{}, reason: &1))
        )

      adapter =
        sequence_adapter([
          {:ok, %{@env | body: timing_out_body}},
          {:ok, %{@env | body: Stream.map(["data: b\n\n"], & &1)}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      error = assert_raise Tesla.Error, fn -> Enum.to_list(env.body) end
      assert error.reason == :recv_chunk_timeout
      assert_received {:request, _}
      refute_received {:request, _}
    end

    test "discard the unfinished event when the stream ends" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "data: a\n\ndata: unfinished"}},
          {:ok, %{@env | body: "data: b\n\n"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      assert Enum.to_list(env.body) == [%{data: "a"}, %{data: "b"}]
    end

    test "do not reconnect while the caller still reads events" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "data: a\n\ndata: b\n\n"}},
          {:ok, %{@env | body: "data: c\n\n"}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      events =
        env.body
        |> Stream.with_index()
        |> Stream.map(fn
          {event, 1} ->
            assert_received {:request, _first}
            refute_received {:request, _second}
            event

          {event, _index} ->
            event
        end)
        |> Enum.take(3)

      assert events == [%{data: "a"}, %{data: "b"}, %{data: "c"}]

      assert_received {:request, _second}
    end

    test "fail when the body is enumerated a second time" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "data: a\n\ndata: b\n\n"}},
          {:ok, %{@env | body: "data: c\n\n"}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      assert Enum.take(env.body, 1) == [%{data: "a"}]
      assert_raise ArgumentError, ~r/once/, fn -> Enum.to_list(env.body) end

      assert_received {:request, _first}
      refute_received {:request, _second}
    end

    test "close the connection when the caller stops reading events" do
      test = self()
      ref = make_ref()

      body =
        Stream.resource(
          fn -> :open end,
          fn :open -> {["data: a\n\n", "data: b\n\n"], :open} end,
          fn _ -> send(test, {:closed, ref}) end
        )

      adapter = sequence_adapter([{:ok, %{@env | body: body}}])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      assert Enum.take(env.body, 1) == [%{data: "a"}]

      assert_received {:closed, ^ref}
    end

    test "close the connection once when reading it raises" do
      assert {:ok, env} = reconnecting(failing_body(fn -> raise "boom" end))

      assert_raise RuntimeError, "boom", fn -> Enum.to_list(env.body) end

      assert_received :body_cleanup
      refute_received :body_cleanup
    end

    test "close the connection once when reading it throws" do
      assert {:ok, env} = reconnecting(failing_body(fn -> throw(:boom) end))

      assert catch_throw(Enum.to_list(env.body)) == :boom

      assert_received :body_cleanup
      refute_received :body_cleanup
    end

    test "close the connection once when reading it exits" do
      assert {:ok, env} = reconnecting(failing_body(fn -> exit(:boom) end))

      assert catch_exit(Enum.to_list(env.body)) == :boom

      assert_received :body_cleanup
      refute_received :body_cleanup
    end

    test "close the connection once when reading it times out" do
      body = failing_body(fn -> raise Tesla.Error, reason: :timeout end)
      assert {:ok, env} = reconnecting(body)

      assert %Tesla.Error{reason: :timeout} = catch_error(Enum.to_list(env.body))

      assert_received :body_cleanup
      refute_received :body_cleanup
    end

    test "keep only the requested key across connections" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "id: 1\ndata: a\n\n"}},
          {:ok, %{@env | body: "data: b\n\n"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 only: :data,
                 reconnect: [delay: 0]
               )

      assert Enum.to_list(env.body) == ["a", "b"]

      assert_received {:request, _first}
      assert_received {:request, second}
      assert Tesla.get_header(second, "last-event-id") == "1"
    end

    test "strip a leading byte order mark from every connection" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "\uFEFFdata: a\n\n"}},
          {:ok, %{@env | body: "\uFEFFdata: b\n\n"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0]
               )

      assert Enum.to_list(env.body) == [%{data: "a"}, %{data: "b"}]
    end

    test "return the first response unchanged when it is not an event stream" do
      adapter =
        sequence_adapter([
          {:ok, %Tesla.Env{status: 200, headers: [{"content-type", "text/plain"}], body: "x"}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: []
               )

      assert env.body == "x"
    end

    test "decode a first response that is an event stream with another status as without reconnecting" do
      response = {:ok, %{@env | status: 500, body: "data: a\n\n"}}

      assert {:ok, expected} =
               Tesla.Middleware.SSE.call(
                 %Tesla.Env{method: :get},
                 [{:fn, sequence_adapter([response])}],
                 []
               )

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(
                 %Tesla.Env{method: :get},
                 [{:fn, sequence_adapter([response])}],
                 reconnect: []
               )

      assert env.status == 500
      assert env.body == [%{data: "a"}]
      assert env.body == expected.body
    end

    test "return the first request error" do
      adapter = sequence_adapter([{:error, :econnrefused}])

      assert {:error, :econnrefused} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: []
               )
    end

    for {key, value, expected} <- [
          {:delay, -1, "expected :delay to be an integer >= 0, got -1"},
          {:delay, 1.5, "expected :delay to be an integer >= 0, got 1.5"},
          {:delay, nil, "expected :delay to be an integer >= 0, got nil"},
          {:delay, "3000", ~s(expected :delay to be an integer >= 0, got "3000")},
          {:max_delay, -1, "expected :max_delay to be an integer >= 0, got -1"},
          {:max_delay, "x", ~s(expected :max_delay to be an integer >= 0, got "x")},
          {:max_attempts, 0, "expected :max_attempts to be an integer >= 1 or :infinity, got 0"},
          {:max_attempts, 2.0,
           "expected :max_attempts to be an integer >= 1 or :infinity, got 2.0"},
          {:max_attempts, nil,
           "expected :max_attempts to be an integer >= 1 or :infinity, got nil"},
          {:max_attempts, "3",
           ~s(expected :max_attempts to be an integer >= 1 or :infinity, got "3")}
        ] do
      test "raise before the request when :#{key} is #{inspect(value)}" do
        adapter = sequence_adapter([{:ok, %{@env | body: "data: a\n\n"}}])

        assert_raise ArgumentError, unquote(expected), fn ->
          Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
            reconnect: [{unquote(key), unquote(value)}]
          )
        end

        refute_received {:request, _}
      end
    end

    test "raise before the request when :delay exceeds :max_delay" do
      adapter = sequence_adapter([{:ok, %{@env | body: "data: a\n\n"}}])

      assert_raise ArgumentError, "expected :delay 5000 not to exceed :max_delay 1000", fn ->
        Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
          reconnect: [delay: 5000, max_delay: 1000]
        )
      end

      refute_received {:request, _}
    end

    test "raise before the request on an unknown reconnect option" do
      adapter = sequence_adapter([{:ok, %{@env | body: "data: a\n\n"}}])

      assert_raise ArgumentError,
                   "unknown :reconnect option :dealy, expected one of [:delay, :max_delay, :max_attempts]",
                   fn ->
                     Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                       reconnect: [dealy: 0]
                     )
                   end

      refute_received {:request, _}
    end

    test "accept zero delay and :infinity max attempts" do
      adapter = sequence_adapter([{:ok, %{@env | body: "data: a\n\n"}}])

      assert {:ok, _env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: [delay: 0, max_attempts: :infinity]
               )
    end

    for invalid <- [3000, "yes", :always, {:delay, 0}] do
      test "raise before the request when the option is #{inspect(invalid)}" do
        adapter = sequence_adapter([{:ok, %{@env | body: "data: a\n\n"}}])

        assert_raise ArgumentError,
                     "expected :reconnect to be a boolean, nil or a keyword list, got #{inspect(unquote(invalid))}",
                     fn ->
                       Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                         reconnect: unquote(Macro.escape(invalid))
                       )
                     end

        refute_received {:request, _}
      end
    end

    test "reconnect with the defaults when the option is true" do
      adapter =
        sequence_adapter([
          {:ok, %{@env | body: "data: a\n\n"}},
          {:ok, %Tesla.Env{status: 204}}
        ])

      assert {:ok, env} =
               Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                 reconnect: true
               )

      assert env.body |> Stream.take(1) |> Enum.to_list() == [%{data: "a"}]
    end

    for disabled <- [false, nil] do
      test "do not reconnect when the option is #{inspect(disabled)}" do
        adapter = sequence_adapter([{:ok, %{@env | body: "data: a\n\n"}}])

        assert {:ok, env} =
                 Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}],
                   reconnect: unquote(disabled)
                 )

        assert env.body == [%{data: "a"}]
        assert_received {:request, _first}
        refute_received {:request, _second}
      end
    end
  end

  defp observed_body do
    test = self()

    Stream.resource(
      fn -> send(test, :rejected_body_opened) end,
      fn state ->
        send(test, :chunk_read)
        {:halt, state}
      end,
      fn _ -> send(test, :rejected_body_closed) end
    )
  end

  defp last_event_id_headers(env) do
    Enum.filter(env.headers, fn {key, _value} -> String.downcase(key) == "last-event-id" end)
  end

  defp failing_body(failure) do
    Stream.resource(
      fn -> :first end,
      fn
        :first -> {["data: a\n\n"], :second}
        :second -> failure.()
      end,
      fn _ -> send(self(), :body_cleanup) end
    )
  end

  defp reconnecting(body) do
    adapter = sequence_adapter([{:ok, %{@env | body: body}}])

    Tesla.Middleware.SSE.call(%Tesla.Env{method: :get}, [{:fn, adapter}], reconnect: [delay: 0])
  end

  defp sequence_adapter(responses) do
    {:ok, agent} = Agent.start_link(fn -> responses end)
    test = self()

    fn env ->
      send(test, {:request, env})
      Agent.get_and_update(agent, fn [response | rest] -> {response, rest} end)
    end
  end

  @request_cap 20

  defp repeating_adapter(responses, last) do
    {:ok, agent} = Agent.start_link(fn -> {responses, 0} end)
    test = self()

    fn _env ->
      send(test, :request)

      Agent.get_and_update(agent, fn
        {_responses, @request_cap} -> {{:ok, %Tesla.Env{status: 204}}, {[], @request_cap}}
        {[], count} -> {last, {[], count + 1}}
        {[response | rest], count} -> {response, {rest, count + 1}}
      end)
    end
  end

  defp requests(count \\ 0) do
    receive do
      :request -> requests(count + 1)
    after
      0 -> count
    end
  end
end
