defmodule JsonTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla.Builder

    plug Tesla.Middleware.EncodeJson
    plug Tesla.Middleware.DecodeJson

    adapter fn (env) ->
      case env.url do
        "/decode" ->
          {200, %{'Content-Type' => 'application/json'}, "{\"value\": 123}"}
        "/encode" ->
          {200, %{'Content-Type' => 'application/json'}, env.body |> String.replace("foo", "baz")}
        "/empty" ->
          {200, %{'Content-Type' => 'application/json'}, nil}
        "/invalid-content-type" ->
          {200, %{'Content-Type' => 'text/plain'}, "hello"}
      end
    end
  end

  test "decode JSON body" do
    assert Client.get("/decode").body == %{"value" => 123}
  end

  test "do not decode empty body" do
    assert Client.get("/empty").body == nil
  end

  test "decode only if Content-Type is application/json" do
    assert Client.get("/invalid-content-type").body == "hello"
  end

  test "encode body as JSON" do
    assert Client.post("/encode", %{"foo" => "bar"}).body == %{"baz" => "bar"}
  end
end
