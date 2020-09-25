defmodule Tesla.Middleware.FormUrlencodedTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.FormUrlencoded

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/post" ->
            {201, [{"content-type", "text/html"}], env.body}

          "/check_incoming_content_type" ->
            {201, [{"content-type", "text/html"}], Tesla.get_header(env, "content-type")}

          "/decode_response" ->
            {200, [{"content-type", "application/x-www-form-urlencoded; charset=utf-8"}],
             "x=1&y=2"}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "encode body as application/x-www-form-urlencoded" do
    assert {:ok, env} = Client.post("/post", %{"foo" => "%bar "})
    assert URI.decode_query(env.body) == %{"foo" => "%bar "}
  end

  test "leave body alone if binary" do
    assert {:ok, env} = Client.post("/post", "data")
    assert env.body == "data"
  end

  test "check header is set as application/x-www-form-urlencoded" do
    assert {:ok, env} = Client.post("/check_incoming_content_type", %{"foo" => "%bar "})
    assert env.body == "application/x-www-form-urlencoded"
  end

  test "decode response" do
    assert {:ok, env} = Client.get("/decode_response")
    assert env.body == %{"x" => "1", "y" => "2"}
  end

  defmodule MultipartClient do
    use Tesla

    plug Tesla.Middleware.FormUrlencoded

    adapter fn %{url: url, body: %Tesla.Multipart{}} = env ->
      {status, headers, body} =
        case url do
          "/upload" ->
            {200, [{"content-type", "text/html"}], "ok"}
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
    assert env.body == "ok"
  end

  defmodule NewEncoderClient do
    use Tesla

    def encoder(_data) do
      "iamencoded"
    end

    plug Tesla.Middleware.FormUrlencoded, encode: &encoder/1

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/post" ->
            {201, [{"content-type", "text/html"}], env.body}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "uses encoder configured in options" do
    {:ok, env} = NewEncoderClient.post("/post", %{"foo" => "bar"})

    assert env.body == "iamencoded"
  end

  defmodule NewDecoderClient do
    use Tesla

    def decoder(_data) do
      "decodedbody"
    end

    plug Tesla.Middleware.FormUrlencoded, decode: &decoder/1

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/post" ->
            {200, [{"content-type", "application/x-www-form-urlencoded; charset=utf-8"}],
             "x=1&y=2"}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "uses decoder configured in options" do
    {:ok, env} = NewDecoderClient.post("/post", %{"foo" => "bar"})

    assert env.body == "decodedbody"
  end

  describe "Encode / Decode" do
    defmodule EncodeDecodeFormUrlencodedClient do
      use Tesla

      plug Tesla.Middleware.DecodeFormUrlencoded
      plug Tesla.Middleware.EncodeFormUrlencoded

      adapter fn env ->
        {status, headers, body} =
          case env.url do
            "/foo2baz" ->
              {200, [{"content-type", "application/x-www-form-urlencoded"}],
               env.body |> String.replace("foo", "baz")}
          end

        {:ok, %{env | status: status, headers: headers, body: body}}
      end
    end

    test "work without options" do
      assert {:ok, env} = EncodeDecodeFormUrlencodedClient.post("/foo2baz", %{"foo" => "bar"})
      assert env.body == %{"baz" => "bar"}
    end
  end
end
