defmodule Tesla.Middleware.FormUrlencodedTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.FormUrlencoded

    adapter fn (env) ->
      {status, headers, body} = case env.url do
        "/post" ->
          {201, %{'Content-Type' => 'text/html'}, env.body}
        "/check_incoming_content_type" ->
          {201, %{'Content-Type' => 'text/html'}, env.headers["content-type"]}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "encode body as application/x-www-form-urlencoded" do
    assert URI.decode_query(Client.post("/post", %{"foo" => "%bar "}).body) == %{"foo" => "%bar "}
  end

  test "leave body alone if binary" do
    assert Client.post("/post", "data").body == "data"
  end

  test "check header is set as application/x-www-form-urlencoded" do
    assert Client.post("/check_incoming_content_type", %{"foo" => "%bar "}).body
      == "application/x-www-form-urlencoded"
  end

  defmodule MultipartClient do
    use Tesla

    plug Tesla.Middleware.FormUrlencoded

    adapter fn (%{url: url, body: %Tesla.Multipart{}} = env) ->
      {status, headers, body} = case url do
        "/upload" ->
          {200, %{'Content-Type' => 'text/html'}, "ok"}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "skips encoding multipart bodies" do
    alias Tesla.Multipart
    mp = Multipart.new
    |> Multipart.add_field("param", "foo")

    assert MultipartClient.post("/upload", mp).body == "ok"
  end
end
