defmodule Tesla.Middleware.KeepRequestTest do
  use ExUnit.Case

  @middleware Tesla.Middleware.KeepRequest

  test "put request metadata into opts" do
    env = %Tesla.Env{url: "my_url", body: "reqbody", headers: [{"x-request", "header"}]}
    assert {:ok, env} = @middleware.call(env, [], [])
    assert env.opts[:req_body] == "reqbody"
    assert env.opts[:req_headers] == [{"x-request", "header"}]
    assert env.opts[:req_url] == "my_url"
  end
end
