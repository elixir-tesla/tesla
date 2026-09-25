defmodule Tesla.Middleware.HeadersTest do
  use ExUnit.Case
  alias Tesla.Env

  @middleware Tesla.Middleware.Headers

  test "merge headers" do
    assert {:ok, env} =
             @middleware.call(%Env{headers: [{"authorization", "secret"}]}, [], [
               {"content-type", "text/plain"}
             ])

    assert env.headers == [{"authorization", "secret"}, {"content-type", "text/plain"}]
  end

  test "puts the value of a Tesla.SecretString on the request" do
    headers = [{"authorization", Tesla.SecretString.new("secret")}, {"user-agent", "Tesla"}]

    assert {:ok, env} = @middleware.call(%Env{}, [], headers)

    assert env.headers == [{"authorization", "secret"}, {"user-agent", "Tesla"}]
  end
end
