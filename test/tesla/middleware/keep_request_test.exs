defmodule Tesla.Middleware.KeepRequestTest do
  use ExUnit.Case

  @middleware Tesla.Middleware.KeepRequest

  test "put request body & headers into opts" do
    env = %Tesla.Env{body: "reqbody", headers: [{"x-request", "header"}]}
    assert {:ok, env} = @middleware.call(env, [], [])
    assert env.opts[:req_body] == "reqbody"
    assert env.opts[:req_headers] == [{"x-request", "header"}]
  end
end
