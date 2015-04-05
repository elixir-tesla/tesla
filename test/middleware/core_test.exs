defmodule CoreTest do
  use ExUnit.Case

  def call(mid, env, opts) do
    mid.call(env, fn a -> a end, opts)
  end

  test "Tesla.Middleware.BaseUrl" do
    env = call(Tesla.Middleware.BaseUrl, %{url: "/path"}, "http://example.com")
    assert env.url == "http://example.com/path"
  end

  test "Tesla.Middleware.Headers" do
    env = call(Tesla.Middleware.Headers, %{headers: %{}}, %{'Content-Type' => 'text/plain'})
    assert env.headers == %{'Content-Type' => 'text/plain'}
  end
end
