defmodule Tesla.Middleware.ClackTest do
  use ExUnit.Case
  alias Tesla.Env

  @middleware Tesla.Middleware.Clack

  test "merge headers" do
    assert {:ok, env} = @middleware.call(%Env{headers: [{"authorization", "secret"}]}, [], [])

    assert env.headers == [{"authorization", "secret"}, {"x-clacks-overhead", "GNU Terry Pratchett"}]
  end

  test "include specified names" do
    assert {:ok, env} = @middleware.call(%Env{headers: [{"authorization", "secret"}]}, [], names: ["Douglas Adams"])

    assert {"x-clacks-overhead", "GNU Terry Pratchett"} in env.headers
    assert {"x-clacks-overhead", "GNU Douglas Adams"} in env.headers
  end
end
