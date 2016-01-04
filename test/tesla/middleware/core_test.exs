defmodule CoreTest do
  use ExUnit.Case

  # TODO: Change order of arguments to (mid, opts, env)
  def call(mid, env, opts) do
    mid.call(env, fn a -> a end, opts)
  end

  test "Tesla.Middleware.BaseUrl" do
    env = call(Tesla.Middleware.BaseUrl, %{url: "/path"}, "http://example.com")
    assert env.url == "http://example.com/path"
  end

  test "Tesla.Middleware.BaseUrl - skip double append" do
    env = call(Tesla.Middleware.BaseUrl, %{url: "http://other.foo"}, "http://example.com")
    assert env.url == "http://other.foo"
  end

  test "Tesla.Middleware.Headers" do
    env = call(Tesla.Middleware.Headers, %{headers: %{}}, %{'Content-Type' => 'text/plain'})
    assert env.headers == %{'Content-Type' => 'text/plain'}
  end

  test "Tesla.Middleware.BaseUrlFromConfig" do
    Application.put_env(:tesla, SomeModule, [base_url: "http://example.com"])
    env = call(Tesla.Middleware.BaseUrlFromConfig, %{url: "/path"}, otp_app: :tesla, module: SomeModule)
    assert env.url == "http://example.com/path"
  end
end
