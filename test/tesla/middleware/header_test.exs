defmodule Tesla.Middleware.HeadersTest do
  use ExUnit.Case
  alias Tesla.Env

  @middleware Tesla.Middleware.Headers

  test "merge headers" do
    env =
      @middleware.call(%Env{headers: %{"Authorization" => "secret"}}, [], %{
        "Content-Type" => "text/plain"
      })

    assert env.headers == %{"Authorization" => "secret", "Content-Type" => "text/plain"}
  end
end
