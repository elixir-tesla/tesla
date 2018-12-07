defmodule Tesla.Middleware.BaseUrlTest do
  use ExUnit.Case
  alias Tesla.Env

  @middleware Tesla.Middleware.BaseUrl

  test "base without slash, path without slash" do
    assert {:ok, env} = @middleware.call(%Env{url: "path"}, [], "http://example.com")
    assert env.url == "http://example.com/path"
  end

  test "base without slash, path with slash" do
    assert {:ok, env} = @middleware.call(%Env{url: "/path"}, [], "http://example.com")
    assert env.url == "http://example.com/path"
  end

  test "base with slash, path without slash" do
    assert {:ok, env} = @middleware.call(%Env{url: "path"}, [], "http://example.com/")
    assert env.url == "http://example.com/path"
  end

  test "base with slash, path with slash" do
    assert {:ok, env} = @middleware.call(%Env{url: "/path"}, [], "http://example.com/")
    assert env.url == "http://example.com/path"
  end

  test "skip double append" do
    assert {:ok, env} = @middleware.call(%Env{url: "http://other.foo"}, [], "http://example.com")
    assert env.url == "http://other.foo"

    assert {:ok, env} = @middleware.call(%Env{url: "https://other.foo"}, [], "http://example.com")
    assert env.url == "https://other.foo"
  end

  test "skip double append on http / https in different case" do
    assert {:ok, env} = @middleware.call(%Env{url: "Http://other.foo"}, [], "http://example.com")
    assert env.url == "Http://other.foo"

    assert {:ok, env} = @middleware.call(%Env{url: "HTTPS://other.foo"}, [], "http://example.com")
    assert env.url == "HTTPS://other.foo"
  end
end
