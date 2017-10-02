defmodule Tesla.Middleware.BaseUrlTest do
  use ExUnit.Case
  alias Tesla.Env

  @middleware Tesla.Middleware.BaseUrl

  test "base without slash, path without slash" do
    env = @middleware.call(%Env{url: "path"}, [], "http://example.com")
    assert env.url == "http://example.com/path"
  end

  test "base without slash, path with slash" do
    env = @middleware.call(%Env{url: "/path"}, [], "http://example.com")
    assert env.url == "http://example.com/path"
  end

  test "base with slash, path without slash" do
    env = @middleware.call(%Env{url: "path"}, [], "http://example.com/")
    assert env.url == "http://example.com/path"
  end

  test "base with slash, path with slash" do
    env = @middleware.call(%Env{url: "/path"}, [], "http://example.com/")
    assert env.url == "http://example.com/path"
  end

  test "skip double append" do
    env = @middleware.call(%Env{url: "http://other.foo"}, [], "http://example.com")
    assert env.url == "http://other.foo"
  end
end
