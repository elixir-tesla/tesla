defmodule Tesla.Middleware.MessagePackTest do
  use ExUnit.Case

  describe "Basics" do
    defmodule Client do
      use Tesla

      plug Tesla.Middleware.MessagePack

      adapter fn env ->
        {status, headers, body} =
          case env.url do
            "/decode" ->
              {200, [{"content-type", "application/msgpack"}], Msgpax.pack!(%{"value" => 123})}

            "/encode" ->
              {200, [{"content-type", "application/msgpack"}],
               env.body |> String.replace("foo", "baz")}

            "/empty" ->
              {200, [{"content-type", "application/msgpack"}], nil}

            "/empty-string" ->
              {200, [{"content-type", "application/msgpack"}], ""}

            "/invalid-content-type" ->
              {200, [{"content-type", "text/plain"}], "hello"}

            "/invalid-msgpack-format" ->
              {200, [{"content-type", "application/msgpack"}], "{\"foo\": bar}"}

            "/raw" ->
              {200, [], env.body}
          end

        {:ok, %{env | status: status, headers: headers, body: body}}
      end
    end

    test "decode MessagePack body" do
      assert {:ok, env} = Client.get("/decode")
      assert env.body == %{"value" => 123}
    end

    test "encode body as MessagePack" do
      body = Msgpax.pack!(%{"foo" => "bar"}, iodata: false)
      assert {:ok, env} = Client.post("/encode", body)
      assert env.body == %{"baz" => "bar"}
    end

    test "do not decode empty body" do
      assert {:ok, env} = Client.get("/empty")
      assert env.body == nil
    end

    test "do not decode empty string body" do
      assert {:ok, env} = Client.get("/empty-string")
      assert env.body == ""
    end

    test "decode only if Content-Type is application/msgpack" do
      assert {:ok, env} = Client.get("/invalid-content-type")
      assert env.body == "hello"
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
      assert {:error, {Tesla.Middleware.MessagePack, :encode, _}} =
               Client.post("/encode", %{pid: self()})
    end

    test "return error when decoding invalid msgpack format" do
      assert {:error, {Tesla.Middleware.MessagePack, :decode, _}} =
               Client.get("/invalid-msgpack-format")
    end
  end

  describe "Custom content type" do
    defmodule CustomContentTypeClient do
      use Tesla

      plug Tesla.Middleware.MessagePack, decode_content_types: ["application/x-custom-msgpack"]

      adapter fn env ->
        {status, headers, body} =
          case env.url do
            "/decode" ->
              {200, [{"content-type", "application/x-custom-msgpack"}],
               Msgpax.pack!(%{"value" => 123})}
          end

        {:ok, %{env | status: status, headers: headers, body: body}}
      end
    end

    test "decode if Content-Type specified in :decode_content_types" do
      assert {:ok, env} = CustomContentTypeClient.get("/decode")
      assert env.body == %{"value" => 123}
    end
  end

  describe "encode/2" do
    test "packs the body and announces the default content type" do
      assert {:ok, env} =
               Tesla.Middleware.MessagePack.encode(%Tesla.Env{body: %{"foo" => "bar"}}, [])

      assert Msgpax.unpack!(env.body) == %{"foo" => "bar"}
      assert Tesla.get_header(env, "content-type") == "application/msgpack"
    end

    test "honours the :encode_content_type option" do
      assert {:ok, env} =
               Tesla.Middleware.MessagePack.encode(%Tesla.Env{body: %{"foo" => "bar"}},
                 encode_content_type: "application/x-msgpack"
               )

      assert Tesla.get_header(env, "content-type") == "application/x-msgpack"
    end

    test "leaves a multipart body alone" do
      multipart = Tesla.Multipart.new() |> Tesla.Multipart.add_field("foo", "bar")

      assert {:ok, env} = Tesla.Middleware.MessagePack.encode(%Tesla.Env{body: multipart}, [])

      assert env.body == multipart
      assert Tesla.get_header(env, "content-type") == nil
    end

    test "uses the :encode option instead of the engine" do
      assert {:ok, env} =
               Tesla.Middleware.MessagePack.encode(%Tesla.Env{body: %{"foo" => "bar"}},
                 encode: fn _body -> {:ok, "packed by hand"} end
               )

      assert env.body == "packed by hand"
    end

    test "reports a body the engine has no implementation for" do
      assert {:error, {Tesla.Middleware.MessagePack, :encode, %Protocol.UndefinedError{}}} =
               Tesla.Middleware.MessagePack.encode(%Tesla.Env{body: %Tesla.Env{}}, [])
    end

    test "rescues a Protocol.UndefinedError raised by a bang encoder" do
      assert {:error, {Tesla.Middleware.MessagePack, :encode, %Protocol.UndefinedError{}}} =
               Tesla.Middleware.MessagePack.encode(%Tesla.Env{body: %Tesla.Env{}},
                 encode: fn body -> {:ok, Msgpax.pack!(body)} end
               )
    end
  end

  describe "decode/2" do
    test "reports a three element error tuple from the :decode option" do
      env = %Tesla.Env{headers: [{"content-type", "application/msgpack"}], body: "bad"}

      assert {:error, {Tesla.Middleware.MessagePack, :decode, :unexpected_byte}} =
               Tesla.Middleware.MessagePack.decode(env,
                 decode: fn _body -> {:error, :unexpected_byte, 0} end
               )
    end
  end

  describe "EncodeMessagePack / DecodeMessagePack" do
    defmodule EncodeDecodeMessagePackClient do
      use Tesla

      plug Tesla.Middleware.DecodeMessagePack
      plug Tesla.Middleware.EncodeMessagePack

      adapter fn env ->
        {status, headers, body} =
          case env.url do
            "/foo2baz" ->
              {200, [{"content-type", "application/msgpack"}],
               env.body |> String.replace("foo", "baz")}
          end

        {:ok, %{env | status: status, headers: headers, body: body}}
      end
    end

    test "EncodeMessagePack / DecodeMessagePack work without options" do
      body = Msgpax.pack!(%{"foo" => "bar"}, iodata: false)
      assert {:ok, env} = EncodeDecodeMessagePackClient.post("/foo2baz", body)
      assert env.body == %{"baz" => "bar"}
    end
  end
end
