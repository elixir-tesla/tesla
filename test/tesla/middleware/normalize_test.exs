defmodule Tesla.Middleware.NormalizeTest do
  use ExUnit.Case
  alias Tesla.Middleware.Normalize

  defp call(args) do
    Normalize.call(struct!(Tesla.Env, args), [], [])
  end

  describe "status" do
    test "when nil" do
      env = call(status: nil)
      assert env.status == nil
    end

    test "when num" do
      env = call(status: 200)
      assert env.status == 200
    end

    test "when string" do
      env = call(status: "200")
      assert env.status == 200
    end

    test "when charlist" do
      env = call(status: '200')
      assert env.status == 200
    end
  end

  describe "body" do
    test "when nil" do
      env = call(body: nil)
      assert env.body == nil
    end

    test "when string" do
      env = call(body: "some-body")
      assert env.body == "some-body"
    end

    test "when charlist" do
      env = call(body: 'some-body')
      assert env.body == "some-body"
    end
  end

  describe "headers" do
    test "when empty list" do
      env = call(headers: [])
      assert env.headers == %{}
    end

    test "when list" do
      env = call(headers: [a: "1", b: 2])
      assert env.headers == %{"a" => "1", "b" => "2"}
    end

    test "when map" do
      env = call(headers: %{"User-Agent" => "tesla"})
      assert env.headers == %{"user-agent" => "tesla"}
    end
  end
end
