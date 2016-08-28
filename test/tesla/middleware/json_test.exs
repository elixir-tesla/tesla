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
        "/invalid-content-type" ->
          {200, %{'Content-Type' => 'text/plain'}, "hello"}
        "/facebook" ->
          {200, %{'Content-Type' => 'text/javascript'}, "{\"friends\": 1000000}"}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  defmodule CustomClient do
    use Tesla

    plug Tesla.Middleware.DecodeJson, engine: Poison, engine_opts: [keys: :atoms]

    adapter fn (env) ->
      case env.url do
        "/decode" ->
          {200, %{'Content-Type' => 'application/json'}, "{\"value\": 123}"}
      end
    end
  end


  test "decode JSON body" do
    assert Client.get("/decode").body == %{"value" => 123}
  end

  test "do not decode empty body" do
    assert Client.get("/empty").body == nil
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
end
