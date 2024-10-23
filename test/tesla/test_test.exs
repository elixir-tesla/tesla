defmodule Tesla.TestTest do
  use ExUnit.Case, async: true

  require Tesla.Test

  describe "html/2" do
    test "sets correct body and content-type header" do
      env = Tesla.Test.html(%Tesla.Env{}, "<html><body>Hello, world!</body></html>")
      assert env.body == "<html><body>Hello, world!</body></html>"
      assert env.headers == [{"content-type", "text/html; charset=utf-8"}]
    end
  end

  describe "json/2" do
    test "encodes map to JSON and sets correct content-type header" do
      env = Tesla.Test.json(%Tesla.Env{}, %{"some" => "data"})
      assert env.body == ~s({"some":"data"})
      assert env.headers == [{"content-type", "application/json; charset=utf-8"}]
    end

    test "does not encode string input" do
      env = Tesla.Test.json(%Tesla.Env{}, "Hello, world!")
      assert env.body == "Hello, world!"
      assert env.headers == [{"content-type", "application/json; charset=utf-8"}]
    end
  end

  describe "text/2" do
    test "sets correct body and content-type header" do
      env = Tesla.Test.text(%Tesla.Env{}, "Hello, world!")
      assert env.body == "Hello, world!"
      assert env.headers == [{"content-type", "text/plain; charset=utf-8"}]
    end
  end

  describe "assert_tesla_env/2" do
    test "excludes specified headers" do
      given =
        %Tesla.Env{}
        |> Tesla.Test.html("<html><body>Hello, world!</body></html>")
        |> Tesla.put_header(
          "traceparent",
          "00-0af7651916cd432186f12bf56043aa3d-b7ad6b7169203331-01"
        )

      expected = Tesla.Test.html(%Tesla.Env{}, "<html><body>Hello, world!</body></html>")

      Tesla.Test.assert_tesla_env(given, expected, exclude_headers: ["traceparent"])
    end

    test "decodes application/json body" do
      given = Tesla.Test.json(%Tesla.Env{}, %{some: "data"})
      expected = Tesla.Test.json(%Tesla.Env{}, %{some: "data"})
      Tesla.Test.assert_tesla_env(given, expected)
    end

    test "compares JSON string with decoded map" do
      given = Tesla.Test.json(%Tesla.Env{}, %{hello: "world"})
      expected = Tesla.Test.json(%Tesla.Env{}, ~s({"hello":"world"}))
      Tesla.Test.assert_tesla_env(given, expected)
    end
  end

  describe "assert_tesla_empty_mailbox/0" do
    test "passes when mailbox is empty" do
      Tesla.Test.assert_tesla_empty_mailbox()
    end

    test "fails when mailbox is not empty" do
      send(self(), {Tesla.Test, :operation})

      assert_raise ExUnit.AssertionError, fn ->
        Tesla.Test.assert_tesla_empty_mailbox()
      end
    end
  end

  describe "assert_received_tesla_call/3" do
    test "passes when expected message is received" do
      send(self(), {Tesla.Test, {Tesla.TeslaMox, :call, [%Tesla.Env{status: 200}, []]}})

      Tesla.Test.assert_received_tesla_call(given_env, given_opts, adapter: Tesla.TeslaMox)
      assert given_env == %Tesla.Env{status: 200}
      assert given_opts == []
    end

    test "fails when no message is received" do
      assert_raise ExUnit.AssertionError, fn ->
        Tesla.Test.assert_received_tesla_call(%Tesla.Env{}, [], adapter: Tesla.TeslaMox)
      end
    end

    test "fails when received message does not match expected pattern" do
      send(
        self(),
        {Tesla.Test, {Tesla.TeslaMox, :call, [%Tesla.Env{url: "https://example.com"}, []]}}
      )

      assert_raise ExUnit.AssertionError, fn ->
        Tesla.Test.assert_received_tesla_call(%Tesla.Env{url: "https://acme.com"}, [],
          adapter: Tesla.TeslaMox
        )
      end
    end
  end
end
