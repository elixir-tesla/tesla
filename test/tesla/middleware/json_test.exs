defmodule Tesla.Middleware.JsonTest do
  use ExUnit.Case

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
        "/raw" ->
          {200, %{}, env.body}
        "/stream" ->
          list = env.body |> Enum.to_list |> Enum.join("---")
          {200, %{}, list}
      end

      %{env | status: status, headers: headers, body: body}
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

  test "do not encode nil body" do
    assert Client.post("/raw", nil).body == nil
  end

  test "do not encode binary body" do
    assert Client.post("/raw", "raw-string").body == "raw-string"
  end

  test "decode if Content-Type is text/javascript" do
    assert Client.get("/facebook").body == %{"friends" => 1000000}
  end

  test "post json stream" do
    stream = Stream.map((1..3), fn i -> %{id: i} end)
    assert env = Client.post("/stream", stream)
    assert env.body == ~s|{"id":1}\n---{"id":2}\n---{"id":3}\n|
  end

  defmodule CustomClient do
    use Tesla

    plug Tesla.Middleware.DecodeJson, engine: Poison, engine_opts: [keys: :atoms]

    adapter fn (env) ->
      {status, headers, body} = case env.url do
        "/decode" ->
          {200, %{'Content-Type' => 'application/json'}, "{\"value\": 123}"}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "decode with custom engine options" do
    assert CustomClient.get("/decode").body == %{value: 123}
  end

  defmodule CustomContentTypeClient do
    use Tesla

    plug Tesla.Middleware.JSON, decode_content_types: ["application/x-custom-json"]

    adapter fn (env) ->
      {status, headers, body} = case env.url do
        "/decode" ->
          {200, %{'Content-Type' => 'application/x-custom-json'}, "{\"value\": 123}"}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "decode if Content-Type specified in :decode_content_types" do
    alias CustomContentTypeClient, as: CCTClient
    assert CCTClient.get("/decode").body == %{"value" => 123}
  end

  defmodule EncodeDecodeJsonClient do
    use Tesla

    plug Tesla.Middleware.DecodeJson
    plug Tesla.Middleware.EncodeJson

    adapter fn (env) ->
      {status, headers, body} = case env.url do
        "/foo2baz" ->
          {200, %{'Content-Type' => 'application/json'}, env.body |> String.replace("foo", "baz")}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "EncodeJson / DecodeJson work without options" do
    alias EncodeDecodeJsonClient, as: EDJClient
    assert EDJClient.post("/foo2baz", %{"foo" => "bar"}).body == %{"baz" => "bar"}
  end

  defmodule MultipartClient do
    use Tesla

    plug Tesla.Middleware.JSON

    adapter fn (%{url: url, body: %Tesla.Multipart{}} = env) ->
      {status, headers, body} = case url do
        "/upload" ->
          {200, %{'Content-Type' => 'application/json'}, "{\"status\": \"ok\"}"}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "skips encoding multipart bodies" do
    alias Tesla.Multipart
    mp = Multipart.new
    |> Multipart.add_field("param", "foo")

    assert MultipartClient.post("/upload", mp).body == %{"status" => "ok"}
  end
end
