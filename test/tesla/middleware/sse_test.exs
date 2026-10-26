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
end
