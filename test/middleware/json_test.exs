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
      end
    end
  end

  test "Tesla.Middleware.DecodeJson" do
    assert Client.get("/decode").body == %{"value" => 123}
  end

  test "Tesla.Middleware.EndcodeJson" do
    assert Client.post("/encode", %{"foo" => "bar"}).body == %{"baz" => "bar"}
  end
end
