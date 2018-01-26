defmodule Tesla.Middleware.JsonTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.JSON

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/decode" ->
            {200, [{"content-type", "application/json"}], "{\"value\": 123}"}

          "/encode" ->
            {200, [{"content-type", "application/json"}],
             env.body |> String.replace("foo", "baz")}

          "/empty" ->
            {200, [{"content-type", "application/json"}], nil}

          "/empty-string" ->
            {200, [{"content-type", "application/json"}], ""}

          "/invalid-content-type" ->
            {200, [{"content-type", "text/plain"}], "hello"}

          "/invalid-json-format" ->
            {200, [{"content-type", "application/json"}], "{\"foo\": bar}"}

          "/invalid-json-encoding" ->
            {200, [{"content-type", "application/json"}],
             <<123, 34, 102, 111, 111, 34, 58, 32, 34, 98, 225, 114, 34, 125>>}

          "/facebook" ->
            {200, [{"content-type", "text/javascript"}], "{\"friends\": 1000000}"}

          "/raw" ->
            {200, [], env.body}

          "/stream" ->
            list = env.body |> Enum.to_list() |> Enum.join("---")
            {200, [], list}
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
    assert Client.get("/facebook").body == %{"friends" => 1_000_000}
  end

  test "post json stream" do
    stream = Stream.map(1..3, fn i -> %{id: i} end)
    assert env = Client.post("/stream", stream)
    assert env.body == ~s|{"id":1}\n---{"id":2}\n---{"id":3}\n|
  end

  test "raise error when decoding invalid json format" do
    assert_raise Tesla.Error, ~r/JSON decode error:/, fn ->
      Client.get("/invalid-json-format")
    end
  end

  test "raise error when decoding non-utf8 json" do
    assert_raise Tesla.Error, ~r/JSON decode error:/, fn ->
      Client.get("/invalid-json-encoding")
    end
  end

  defmodule CustomClient do
    use Tesla

    plug Tesla.Middleware.DecodeJson, engine: Poison, engine_opts: [keys: :atoms]

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/decode" ->
            {200, [{"content-type", "application/json"}], "{\"value\": 123}"}
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

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/decode" ->
            {200, [{"content-type", "application/x-custom-json"}], "{\"value\": 123}"}
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

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/foo2baz" ->
            {200, [{"content-type", "application/json"}],
             env.body |> String.replace("foo", "baz")}
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

    adapter fn %{url: url, body: %Tesla.Multipart{}} = env ->
      {status, headers, body} =
        case url do
          "/upload" ->
            {200, [{"content-type", "application/json"}], "{\"status\": \"ok\"}"}
        end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "skips encoding multipart bodies" do
    alias Tesla.Multipart

    mp =
      Multipart.new()
      |> Multipart.add_field("param", "foo")

    assert MultipartClient.post("/upload", mp).body == %{"status" => "ok"}
  end
end
