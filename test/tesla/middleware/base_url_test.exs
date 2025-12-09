defmodule Tesla.Middleware.BaseUrlTest do
  use ExUnit.Case, async: true
  alias Tesla.Env

  @middleware Tesla.Middleware.BaseUrl

  test "base without slash, empty path" do
    assert {:ok, env} = @middleware.call(%Env{url: ""}, [], "http://example.com")
    assert env.url == "http://example.com"
  end

  test "base with slash, empty path" do
    assert {:ok, env} = @middleware.call(%Env{url: ""}, [], "http://example.com/")
    assert env.url == "http://example.com/"
  end

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

  test "base and path without slash, empty path" do
    assert {:ok, env} = @middleware.call(%Env{url: ""}, [], "http://example.com/top")
    assert env.url == "http://example.com/top"
  end

  test "base and path with slash, empty path" do
    assert {:ok, env} = @middleware.call(%Env{url: ""}, [], "http://example.com/top/")
    assert env.url == "http://example.com/top/"
  end

  test "base and path without slash, path without slash" do
    assert {:ok, env} = @middleware.call(%Env{url: "path"}, [], "http://example.com/top")
    assert env.url == "http://example.com/top/path"
  end

  test "base and path without slash, path with slash" do
    assert {:ok, env} = @middleware.call(%Env{url: "/path"}, [], "http://example.com/top")
    assert env.url == "http://example.com/top/path"
  end

  test "base and path with slash, path without slash" do
    assert {:ok, env} = @middleware.call(%Env{url: "path"}, [], "http://example.com/top/")
    assert env.url == "http://example.com/top/path"
  end

  test "base and path with slash, path with slash" do
    assert {:ok, env} = @middleware.call(%Env{url: "/path"}, [], "http://example.com/top/")
    assert env.url == "http://example.com/top/path"
  end

  test "skip double append on http / https" do
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

  test "strict policy: prepend base url even with http scheme" do
    assert {:ok, env} =
             @middleware.call(
               %Env{url: "http://other.foo"},
               [],
               base_url: "http://example.com",
               policy: :strict
             )

    assert env.url == "http://example.com/http://other.foo"
  end

  test "strict policy: prepend base url even with https scheme" do
    assert {:ok, env} =
             @middleware.call(
               %Env{url: "https://other.foo"},
               [],
               base_url: "http://example.com",
               policy: :strict
             )

    assert env.url == "http://example.com/https://other.foo"
  end

  test "strict policy: still works with relative paths" do
    assert {:ok, env} =
             @middleware.call(%Env{url: "/path"}, [],
               base_url: "http://example.com",
               policy: :strict
             )

    assert env.url == "http://example.com/path"
  end

  test "strict policy: case insensitive scheme detection" do
    assert {:ok, env} =
             @middleware.call(
               %Env{url: "HTTP://other.foo"},
               [],
               base_url: "http://example.com",
               policy: :strict
             )

    assert env.url == "http://example.com/HTTP://other.foo"

    assert {:ok, env} =
             @middleware.call(
               %Env{url: "HTTPS://other.foo"},
               [],
               base_url: "http://example.com",
               policy: :strict
             )

    assert env.url == "http://example.com/HTTPS://other.foo"
  end

  test "default policy (no policy): respects permissive behavior" do
    assert {:ok, env} =
             @middleware.call(%Env{url: "http://other.foo"}, [], base_url: "http://example.com")

    assert env.url == "http://other.foo"
  end

  test "backward compatibility: string base url works with new implementation" do
    assert {:ok, env} = @middleware.call(%Env{url: "http://other.foo"}, [], "http://example.com")
    assert env.url == "http://other.foo"

    assert {:ok, env} = @middleware.call(%Env{url: "/path"}, [], "http://example.com")
    assert env.url == "http://example.com/path"
  end

  test "policy validation: accepts valid policy values" do
    assert {:ok, env} =
             @middleware.call(
               %Env{url: "http://other.foo"},
               [],
               base_url: "http://example.com",
               policy: :strict
             )

    assert env.url == "http://example.com/http://other.foo"

    assert {:ok, env} =
             @middleware.call(
               %Env{url: "http://other.foo"},
               [],
               base_url: "http://example.com",
               policy: :insecure
             )

    assert env.url == "http://other.foo"
  end

  test "policy validation: raises error for invalid policy values" do
    assert_raise ArgumentError, "invalid policy :strikt, expected :strict or :insecure", fn ->
      @middleware.call(
        %Env{url: "http://other.foo"},
        [],
        base_url: "http://example.com",
        policy: :strikt
      )
    end

    assert_raise ArgumentError, "invalid policy :secure, expected :strict or :insecure", fn ->
      @middleware.call(
        %Env{url: "http://other.foo"},
        [],
        base_url: "http://example.com",
        policy: :secure
      )
    end

    assert_raise ArgumentError, "invalid policy \"strict\", expected :strict or :insecure", fn ->
      @middleware.call(
        %Env{url: "http://other.foo"},
        [],
        base_url: "http://example.com",
        policy: "strict"
      )
    end

    assert_raise ArgumentError, "invalid policy 123, expected :strict or :insecure", fn ->
      @middleware.call(
        %Env{url: "http://other.foo"},
        [],
        base_url: "http://example.com",
        policy: 123
      )
    end
  end

  test "edge case: empty string base_url" do
    assert {:ok, env} = @middleware.call(%Env{url: "/path"}, [], "")
    assert env.url == "/path"

    assert {:ok, env} = @middleware.call(%Env{url: "path"}, [], "")
    assert env.url == "path"

    assert {:ok, env} = @middleware.call(%Env{url: ""}, [], "")
    assert env.url == ""

    assert {:ok, env} = @middleware.call(%Env{url: "http://example.com"}, [], "")
    assert env.url == "http://example.com"

    assert {:ok, env} = @middleware.call(%Env{url: "/path"}, [], base_url: "")
    assert env.url == "/path"
  end

  test "edge case: empty string base_url with strict policy" do
    assert {:ok, env} =
             @middleware.call(
               %Env{url: "http://example.com"},
               [],
               base_url: "",
               policy: :strict
             )

    assert env.url == "http://example.com"

    assert {:ok, env} =
             @middleware.call(
               %Env{url: "/path"},
               [],
               base_url: "",
               policy: :strict
             )

    assert env.url == "/path"
  end

  test "error handling: invalid base_url types" do
    assert_raise ArgumentError, "base_url must be a string but got nil", fn ->
      @middleware.call(%Env{url: "/path"}, [], base_url: nil)
    end

    assert_raise ArgumentError, "base_url must be a string but got :invalid", fn ->
      @middleware.call(%Env{url: "/path"}, [], base_url: :invalid)
    end

    assert_raise ArgumentError, "base_url must be a string but got 123", fn ->
      @middleware.call(%Env{url: "/path"}, [], base_url: 123)
    end

    # Missing :base_url key (same error as nil)
    assert_raise ArgumentError, "base_url must be a string but got nil", fn ->
      @middleware.call(%Env{url: "/path"}, [], policy: :strict)
    end

    assert_raise ArgumentError, "base_url must be a string but got nil", fn ->
      @middleware.call(%Env{url: "/path"}, [], [])
    end
  end
end
