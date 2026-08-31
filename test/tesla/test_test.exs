defmodule Tesla.TestTest do
  use ExUnit.Case, async: true

  import Mox

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

  describe "put_headers/2" do
    test "sets the headers when the env carries none" do
      env = Tesla.Test.text(%Tesla.Env{headers: nil}, "Hello, world!")
      assert env.headers == [{"content-type", "text/plain; charset=utf-8"}]
    end

    test "appends to the headers the env already carries" do
      env = Tesla.Test.text(%Tesla.Env{headers: [{"x-request-id", "abc"}]}, "Hello, world!")

      assert env.headers == [
               {"x-request-id", "abc"},
               {"content-type", "text/plain; charset=utf-8"}
             ]
    end
  end

  describe "assert_tesla_env/3 body decoding" do
    test "decodes an application/json body into an atom-keyed map" do
      given =
        %Tesla.Env{body: ~s({"some":"data"})}
        |> Tesla.put_header("content-type", "application/json")

      Tesla.Test.assert_tesla_env(given, %Tesla.Env{
        body: %{some: "data"},
        headers: [{"content-type", "application/json"}]
      })
    end

    test "decodes an application/x-www-form-urlencoded body into a string-keyed map" do
      given =
        %Tesla.Env{body: "name=tesla&lang=elixir"}
        |> Tesla.put_header("content-type", "application/x-www-form-urlencoded")

      Tesla.Test.assert_tesla_env(given, %Tesla.Env{
        body: %{"name" => "tesla", "lang" => "elixir"},
        headers: [{"content-type", "application/x-www-form-urlencoded"}]
      })
    end

    test "leaves a content-type carrying parameters undecoded" do
      given = Tesla.Test.json(%Tesla.Env{}, %{some: "data"})

      Tesla.Test.assert_tesla_env(given, %Tesla.Env{
        body: ~s({"some":"data"}),
        headers: [{"content-type", "application/json; charset=utf-8"}]
      })

      assert_raise ExUnit.AssertionError, fn ->
        Tesla.Test.assert_tesla_env(given, %Tesla.Env{
          body: %{some: "data"},
          headers: [{"content-type", "application/json; charset=utf-8"}]
        })
      end
    end

    test "leaves a body without a content-type undecoded" do
      Tesla.Test.assert_tesla_env(%Tesla.Env{body: "raw"}, %Tesla.Env{body: "raw"})
    end
  end

  describe "assert_tesla_env/3 mismatches" do
    test "fails on a different method" do
      assert_raise ExUnit.AssertionError, fn ->
        Tesla.Test.assert_tesla_env(%Tesla.Env{method: :post}, %Tesla.Env{method: :get})
      end
    end

    test "fails on a different url" do
      assert_raise ExUnit.AssertionError, fn ->
        Tesla.Test.assert_tesla_env(
          %Tesla.Env{url: "https://acme.com"},
          %Tesla.Env{url: "https://example.com"}
        )
      end
    end

    test "fails on a different query" do
      assert_raise ExUnit.AssertionError, fn ->
        Tesla.Test.assert_tesla_env(%Tesla.Env{query: [page: 1]}, %Tesla.Env{query: [page: 2]})
      end
    end

    test "fails on a different body" do
      assert_raise ExUnit.AssertionError, fn ->
        Tesla.Test.assert_tesla_env(%Tesla.Env{body: "given"}, %Tesla.Env{body: "expected"})
      end
    end

    test "fails on a header the expectation does not carry" do
      given = Tesla.put_header(%Tesla.Env{}, "traceparent", "00-0af7-b7ad-01")

      assert_raise ExUnit.AssertionError, fn ->
        Tesla.Test.assert_tesla_env(given, %Tesla.Env{})
      end
    end

    test "fails on a header excluded under a different key" do
      given = Tesla.put_header(%Tesla.Env{}, "traceparent", "00-0af7-b7ad-01")

      assert_raise ExUnit.AssertionError, fn ->
        Tesla.Test.assert_tesla_env(given, %Tesla.Env{}, exclude_headers: ["authorization"])
      end
    end
  end

  describe "expect_tesla_call/1" do
    setup :verify_on_exit!

    test "merges the returned status, body and headers onto the request env" do
      Tesla.Test.expect_tesla_call(
        times: 1,
        returns: %Tesla.Env{status: 201, body: "OK", headers: [{"x-trace", "1"}]},
        adapter: Tesla.TestSupport.MockAdapter
      )

      assert {:ok, env} = Tesla.post(client(), "https://acme.com/users", "some-data")
      assert env.status == 201
      assert env.body == "OK"
      assert env.headers == [{"x-trace", "1"}]
      assert env.method == :post
      assert env.url == "https://acme.com/users"
    end

    test "delegates to the returned function" do
      Tesla.Test.expect_tesla_call(
        times: 1,
        returns: fn given_env, given_opts ->
          {:ok, %{given_env | status: 200, body: {given_env.url, given_opts}}}
        end,
        adapter: Tesla.TestSupport.MockAdapter
      )

      assert {:ok, env} = Tesla.get(client(), "https://acme.com/users")
      assert env.body == {"https://acme.com/users", []}
    end

    test "returns the given error" do
      Tesla.Test.expect_tesla_call(
        times: 1,
        returns: {:error, :econnrefused},
        adapter: Tesla.TestSupport.MockAdapter
      )

      assert {:error, :econnrefused} = Tesla.get(client(), "https://acme.com/users")
    end

    test "expects the call the given number of times" do
      Tesla.Test.expect_tesla_call(
        times: 2,
        returns: %Tesla.Env{status: 200},
        adapter: Tesla.TestSupport.MockAdapter
      )

      assert {:ok, _} = Tesla.get(client(), "https://acme.com/users")
      assert {:ok, _} = Tesla.get(client(), "https://acme.com/users")

      Tesla.Test.assert_received_tesla_call(_env, _opts, adapter: Tesla.TestSupport.MockAdapter)
      Tesla.Test.assert_received_tesla_call(_env, _opts, adapter: Tesla.TestSupport.MockAdapter)
      Tesla.Test.assert_tesla_empty_mailbox()
    end

    test "sends the call to the given process" do
      parent = self()

      collector =
        spawn_link(fn ->
          receive do
            message -> send(parent, {:collected, message})
          end
        end)

      Tesla.Test.expect_tesla_call(
        times: 1,
        returns: %Tesla.Env{status: 200},
        send_to: collector,
        adapter: Tesla.TestSupport.MockAdapter
      )

      assert {:ok, _} = Tesla.get(client(), "https://acme.com/users")

      assert_receive {:collected, {Tesla.Test, {Tesla.TestSupport.MockAdapter, :call, [env, []]}}}

      assert env.url == "https://acme.com/users"

      Tesla.Test.assert_tesla_empty_mailbox()
    end

    test "sends nothing when send_to is nil" do
      Tesla.Test.expect_tesla_call(
        times: 1,
        returns: %Tesla.Env{status: 200},
        send_to: nil,
        adapter: Tesla.TestSupport.MockAdapter
      )

      assert {:ok, _} = Tesla.get(client(), "https://acme.com/users")

      Tesla.Test.assert_tesla_empty_mailbox()
    end
  end

  defp client, do: Tesla.client([], Tesla.TestSupport.MockAdapter)
end

defmodule Tesla.TestAdapterResolutionTest do
  use ExUnit.Case, async: false

  import Mox

  setup do
    on_exit(fn -> Application.delete_env(:tesla, :adapter) end)
    :ok
  end

  test "falls back to the adapter configured for the application" do
    Application.put_env(:tesla, :adapter, Tesla.TestSupport.MockAdapter)

    Tesla.Test.expect_tesla_call(times: 1, returns: %Tesla.Env{status: 200})

    client = Tesla.client([], Tesla.TestSupport.MockAdapter)
    assert {:ok, env} = Tesla.get(client, "https://acme.com/users")
    assert env.status == 200

    verify!(Tesla.TestSupport.MockAdapter)
  end

  test "raises when no adapter is configured" do
    Application.delete_env(:tesla, :adapter)

    assert_raise ArgumentError, ~r/expected :adapter to be defined/, fn ->
      Tesla.Test.expect_tesla_call(times: 1, returns: %Tesla.Env{status: 200})
    end
  end
end
