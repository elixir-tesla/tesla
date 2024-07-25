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
  end
end
