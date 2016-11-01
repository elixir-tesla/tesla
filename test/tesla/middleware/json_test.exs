defmodule JsonTest do
  use ExUnit.Case

  use Tesla.Middleware.TestCase, middleware: Tesla.Middleware.JSON
  use Tesla.Middleware.TestCase, middleware: Tesla.Middleware.DecodeJson
  use Tesla.Middleware.TestCase, middleware: Tesla.Middleware.EncodeJson


  defmodule Client do
    use Tesla

    plug Tesla.Middleware.JSON

    adapter fn (env) ->
      {status, headers, body} = case env.url do
        "/decode" ->
          {200, %{'Content-Type' => 'application/json'}, "{\"value\": 123}"}
        "/encode" ->
          {200, %{'Content-Type' => 'application/json'}, env.body |> String.replace("foo", "baz")}
        "/empty" ->
          {200, %{'Content-Type' => 'application/json'}, nil}
        "/empty-string" ->
          {200, %{'Content-Type' => 'application/json'}, ""}
        "/invalid-content-type" ->
          {200, %{'Content-Type' => 'text/plain'}, "hello"}
        "/facebook" ->
          {200, %{'Content-Type' => 'text/javascript'}, "{\"friends\": 1000000}"}

        "/stream1" -> stream [~s|{"aa":1}\r\n{"bb":2}\r\n{"cc":3}\r\n|]
        "/stream2" -> stream [~s|{"aa":1}\r\n|, ~s|{"bb":2}\r\n|, ~s|{"cc":3}\r\n|]
        "/stream3" -> stream [~s|{"a|, ~s|a":1}\r|, ~s|\n{"bb":2}|, ~s|\r\n{"cc":3}\r\n|]
        "/stream4" -> stream [~s|{|, ~s|"|, ~s|a|, ~s|a":1|, ~s|}\r\n{"bb":2}\r\n{"cc":3}\r\n|]
        "/stream5" -> stream [~s|{"aa":1}\r\n{"|, ~s|b|, ~s|b|, ~s|":2}\r\n{"cc":3}\r\n|]
        "/stream6" -> stream [~s|{"aa":1}|, ~s|\r|, ~s|\n|, ~s|{"bb":2}\r\n{"cc":3}\r\n|]
      end

      %{env | status: status, headers: headers, body: body}
    end

    defp stream(data) do
      {200, %{'Content-Type' => 'application/json'}, Stream.concat(data, [])}
    end
  end

  test "decode JSON body" do
    assert Client.get("/decode").body == %{"value" => 123}
  end

  test "do not decode empty body" do
    assert Client.get("/empty").body == nil
  end

  test "do not decode empty string body" do
    assert Client.get("/empty-string").body == ""
  end

  test "decode only if Content-Type is application/json or test/json" do
    assert Client.get("/invalid-content-type").body == "hello"
  end

  test "encode body as JSON" do
    assert Client.post("/encode", %{"foo" => "bar"}).body == %{"baz" => "bar"}
  end

  test "decode if Content-Type is text/javascript" do
    assert Client.get("/facebook").body == %{"friends" => 1000000}
  end

  test "decode stream 1", do: test_stream(1)
  test "decode stream 2", do: test_stream(2)
  test "decode stream 3", do: test_stream(3)
  test "decode stream 4", do: test_stream(4)
  test "decode stream 5", do: test_stream(5)
  test "decode stream 6", do: test_stream(6)

  @stream_response [%{"aa" => 1}, %{"bb" => 2}, %{"cc" => 3}]
  defp test_stream(i) do
    assert Client.get("/stream#{i}", opts: [stream_response: true]).body |> Enum.to_list == @stream_response
  end
end
