defmodule Tesla.SecretStringTest do
  use ExUnit.Case, async: true
  doctest Tesla.SecretString

  alias Tesla.SecretString

  test "inspect never prints the value, at any nesting" do
    secret = SecretString.new("Bearer s3cret")

    assert inspect(secret) == "#Tesla.SecretString<redacted>"
    refute inspect([{"authorization", secret}]) =~ "s3cret"
    refute inspect(%{opts: [token: secret]}, pretty: true) =~ "s3cret"
  end

  test "to_string and interpolation return the value" do
    secret = SecretString.new("s3cret")

    assert to_string(secret) == "s3cret"
    assert "Bearer #{secret}" == "Bearer s3cret"
  end

  test "a client holding secrets in middleware options does not print them" do
    client =
      Tesla.client([
        {Tesla.Middleware.Headers, [{"authorization", SecretString.new("Bearer s3cret-1")}]},
        {Tesla.Middleware.BearerAuth, token: SecretString.new("s3cret-2")},
        {Tesla.Middleware.BasicAuth, %{username: "u", password: SecretString.new("s3cret-3")}}
      ])

    refute inspect(client) =~ "s3cret"
    refute inspect(%Tesla.Env{__client__: client}) =~ "s3cret"
  end
end
