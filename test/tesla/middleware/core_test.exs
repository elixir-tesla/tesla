defmodule CoreTest do
  use ExUnit.Case

  test "Tesla.Middleware.BaseUrlFromConfig" do
    Application.put_env(:tesla, SomeModule, [base_url: "http://example.com"])
    env = Tesla.Middleware.BaseUrlFromConfig.call %Tesla.Env{url: "/path"}, [], otp_app: :tesla, module: SomeModule
    assert env.url == "http://example.com/path"
  end
end
