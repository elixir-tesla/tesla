defmodule Tesla.Middleware.JsonTest do
  use ExUnit.Case

  describe "Basics" do
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

        {:ok, %{env | status: status, headers: headers, body: body}}
      end
    end

    test "decode JSON body" do
      assert {:ok, env} = Client.get("/decode")
      assert env.body == %{"value" => 123}
    end

    test "do not decode empty body" do
      assert {:ok, env} = Client.get("/empty")
      assert env.body == nil
    end

    test "do not decode empty string body" do
      assert {:ok, env} = Client.get("/empty-string")
      assert env.body == ""
    end

    test "decode only if Content-Type is application/json or test/json" do
      assert {:ok, env} = Client.get("/invalid-content-type")
      assert env.body == "hello"
    end

    test "encode body as JSON" do
      assert {:ok, env} = Client.post("/encode", %{"foo" => "bar"})
      assert env.body == %{"baz" => "bar"}
    end

    test "do not encode nil body" do
      assert {:ok, env} = Client.post("/raw", nil)
      assert env.body == nil
    end

    test "do not encode binary body" do
      assert {:ok, env} = Client.post("/raw", "raw-string")
      assert env.body == "raw-string"
    end

    test "return error on encoding error" do
      assert {:error, {Tesla.Middleware.JSON, :encode, _}} =
               Client.post("/encode", %{pid: self()})
    end

    test "decode if Content-Type is text/javascript" do
      assert {:ok, env} = Client.get("/facebook")
      assert env.body == %{"friends" => 1_000_000}
    end

    test "post json stream" do
      stream = Stream.map(1..3, fn i -> %{id: i} end)
      assert {:ok, env} = Client.post("/stream", stream)
      assert env.body == ~s|{"id":1}\n---{"id":2}\n---{"id":3}\n|
    end

    test "return error when decoding invalid json format" do
      assert {:error, {Tesla.Middleware.JSON, :decode, _}} = Client.get("/invalid-json-format")
    end

    test "raise error when decoding non-utf8 json" do
      assert {:error, {Tesla.Middleware.JSON, :decode, _}} = Client.get("/invalid-json-encoding")
    end
  end

  describe "Custom content type" do
    defmodule CustomContentTypeClient do
      use Tesla

      plug Tesla.Middleware.JSON, decode_content_types: ["application/x-custom-json"]

      adapter fn env ->
        {status, headers, body} =
          case env.url do
            "/decode" ->
              {200, [{"content-type", "application/x-custom-json"}], "{\"value\": 123}"}
          end

        {:ok, %{env | status: status, headers: headers, body: body}}
      end
    end

    test "decode if Content-Type specified in :decode_content_types" do
      assert {:ok, env} = CustomContentTypeClient.get("/decode")
      assert env.body == %{"value" => 123}
    end

    test "set custom request Content-Type header specified in :encode_content_type" do
      assert {:ok, env} =
               Tesla.Middleware.JSON.call(
                 %Tesla.Env{body: %{"foo" => "bar"}},
                 [],
                 encode_content_type: "application/x-other-custom-json"
               )

      assert Tesla.get_header(env, "content-type") == "application/x-other-custom-json"
    end
  end

  describe "EncodeJson / DecodeJson" do
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

        {:ok, %{env | status: status, headers: headers, body: body}}
      end
    end

    test "EncodeJson / DecodeJson work without options" do
      assert {:ok, env} = EncodeDecodeJsonClient.post("/foo2baz", %{"foo" => "bar"})
      assert env.body == %{"baz" => "bar"}
    end
  end

  describe "Multipart" do
    defmodule MultipartClient do
      use Tesla

      plug Tesla.Middleware.JSON

      adapter fn %{url: url, body: %Tesla.Multipart{}} = env ->
        {status, headers, body} =
          case url do
            "/upload" ->
              {200, [{"content-type", "application/json"}], "{\"status\": \"ok\"}"}
          end

        {:ok, %{env | status: status, headers: headers, body: body}}
      end
    end

    test "skips encoding multipart bodies" do
      alias Tesla.Multipart

      mp =
        Multipart.new()
        |> Multipart.add_field("param", "foo")

      assert {:ok, env} = MultipartClient.post("/upload", mp)
      assert env.body == %{"status" => "ok"}
    end
  end

  describe "Engine: poison" do
    defmodule PoisonClient do
      use Tesla

      plug Tesla.Middleware.JSON, engine: Poison, engine_opts: [keys: :atoms]

      adapter fn env ->
        {status, headers, body} =
          case env.url do
            "/decode" ->
              {200, [{"content-type", "application/json"}], "{\"value\": 123}"}
          end

        {:ok, %{env | status: status, headers: headers, body: body}}
      end
    end

    test "decode with custom engine options" do
      assert {:ok, env} = PoisonClient.get("/decode")
      assert env.body == %{value: 123}
    end
  end

  describe "Engine: jason" do
    defmodule JasonClient do
      use Tesla

      plug Tesla.Middleware.JSON, engine: Jason

      adapter fn env ->
        {:ok,
         %{
           env
           | status: 200,
             headers: [{"content-type", "application/json"}],
             body: ~s|{"value": 123}|
         }}
      end
    end

    test "decode with custom engine options" do
      assert {:ok, env} = JasonClient.get("/decode")
      assert env.body == %{"value" => 123}
    end
  end

  describe "Engine: exjsx" do
    defmodule JsxClient do
      use Tesla

      plug Tesla.Middleware.JSON, engine: JSX

      adapter fn env ->
        {:ok,
         %{
           env
           | status: 200,
             headers: [{"content-type", "application/json"}],
             body: ~s|{"value": 123}|
         }}
      end
    end

    test "decode with custom engine options" do
      assert {:ok, env} = JsxClient.get("/decode")
      assert env.body == %{"value" => 123}
    end
  end
end
