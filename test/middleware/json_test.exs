defmodule JsonTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla.Builder

    with Tesla.Middleware.EncodeJson
    with Tesla.Middleware.DecodeJson

    adapter fn (env) ->
      case env.url do
        "/decode" ->
          {200, %{}, "{\"value\": 123}"}
        "/encode" ->
          {200, %{}, env.body |> String.replace("foo", "baz")}
        "/empty" ->
          {200, %{}, nil}
      end
    end
  end

  test "decode JSON body" do
    assert Client.get("/decode").body == %{"value" => 123}
  end

  test "do not decode empty body" do
    assert Client.get("/empty").body == nil
  end

  test "encode body as JSON" do
    assert Client.post("/encode", %{"foo" => "bar"}).body == %{"baz" => "bar"}
  end
end
