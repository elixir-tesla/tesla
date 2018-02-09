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
end
