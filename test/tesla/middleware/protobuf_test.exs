defmodule ProtobufTest do
  use ExUnit.Case

  use Tesla.Middleware.TestCase, middleware: Tesla.Middleware.Protobuf
  use Tesla.Middleware.TestCase, middleware: Tesla.Middleware.DecodeProtobuf
  use Tesla.Middleware.TestCase, middleware: Tesla.Middleware.EncodeProtobuf

  defmodule Proto do
    use Protobuf, "
      message Message1 {
        optional string message_body = 1;
      }

      message Message2 {
        optional bool test = 1;
      }
    "
  end

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Protobuf, engine: Proto.Message1

    adapter fn (env) ->
      {status, headers, body} = case env.url do
        "/decode" ->
          response = %Proto.Message1{message_body: "decode"}
          {200, %{'Content-Type' => 'application/x-protobuf'}, Proto.Message1.encode(response)}
        "/encode" ->
          {200, %{'Content-Type' => 'text/plain'}, Proto.Message1.decode(env.body).message_body}
        "/encode_decode" ->
          {200, %{'Content-Type' => 'application/x-protobuf'}, env.body}
        "/empty" ->
          {200, %{'Content-Type' => 'application/x-protobuf'}, nil}
        "/empty-string" ->
          {200, %{'Content-Type' => 'application/x-protobuf'}, ""}
        "/invalid-content-type" ->
          {200, %{'Content-Type' => 'text/plain'}, "hello"}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "decode binary body" do
    assert Client.get("/decode").body == %Proto.Message1{message_body: "decode"}
  end

  test "do not decode empty body" do
    assert Client.get("/empty").body == nil
  end

  test "do not decode empty string body" do
    assert Client.get("/empty-string").body == ""
  end

  test "decode only if Content-Type is application/x-protobuf" do
    assert Client.get("/invalid-content-type").body == "hello"
  end

  test "encode body as Protobuf" do
    proto = %Proto.Message1{message_body: "encode"}
    assert Client.post("/encode", proto).body == "encode"
  end

  test "send already encoded data" do
    proto = %Proto.Message1{message_body: "encode"} |> Proto.Message1.encode()
    assert Client.post("/encode", proto).body == "encode"
  end

  test "encode/decode same message type using engine option" do
    proto = %Proto.Message1{message_body: "encode/decode"}
    assert Client.post("/encode_decode", proto).body == proto
  end

  defmodule EncodeDecodeClient do
    use Tesla

    plug Tesla.Middleware.EncodeProtobuf, encode: &Proto.Message1.encode/1
    plug Tesla.Middleware.DecodeProtobuf, decode: &Proto.Message2.decode/1

    adapter fn (env) ->
      {status, headers, body} = case env.url do
        "/" ->
          request = Proto.Message1.decode(env.body).message_body
          response = %Proto.Message2{test: request == "encode"} |> Proto.Message2.encode()
          {200, %{'Content-Type' => 'application/x-protobuf'}, response}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  alias EncodeDecodeClient, as: EDClient

  test "encode/decode different messages" do
    request = %Proto.Message1{message_body: "encode"}
    assert EDClient.post("/", request).body == %Proto.Message2{test: true}
  end

  defmodule InvalidClient do
    use Tesla

    plug Tesla.Middleware.Protobuf

    adapter fn (env) ->
      {status, headers, body} = case env.url do
        "/" ->
          response = %Proto.Message2{test: true} |> Proto.Message2.encode()
          {200, %{'Content-Type' => 'application/x-protobuf'}, response}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "raise error when protobuf middleware config is missing" do
    assert_raise Tesla.Error, "insufficient protobuf middleware configuration", fn-> InvalidClient.get("/") end
  end
end
