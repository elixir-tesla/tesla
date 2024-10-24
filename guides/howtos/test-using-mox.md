# Test Using Mox

To mock HTTP requests in your tests using Mox with the Tesla HTTP client,
follow these steps:

## 1. Define a Mock Adapter

First, define a mock adapter that implements the Tesla.Adapter behaviour. This
adapter will intercept HTTP requests during testing.

Create a file at `test/support/mocks.ex`:

```elixir
# test/support/mocks.ex
Mox.defmock(MyApp.MockAdapter, for: Tesla.Adapter)
```

## 2. Configure the Mock Adapter for Tests

In your `config/test.exs` file, configure Tesla to use the mock adapter you
just defined:

```elixir
# config/test.exs
config :tesla, adapter: MyApp.MockAdapter
```

If you are not using the global adapter configuration, ensure that your Tesla
client modules are configured to use `MyApp.MockAdapter` during tests.

## 3. Set Up Mocking in Your Tests

Create a test module, for example `test/demo_test.exs`, and set up `Mox` to
define expectations and verify them:

```elixir
defmodule MyApp.FeatureTest do
  use ExUnit.Case, async: true

  require Tesla.Test

  setup context, do: Mox.set_mox_from_context(context)
  setup context, do: Mox.verify_on_exit!(context)

  test "example test" do
    #--------- Given - Stubs and Preconditions
    # Expect a single HTTP request to be made and return a JSON response
    Tesla.Test.expect_tesla_call(
      times: 1,
      returns: Tesla.Test.json(%Tesla.Env{status: 200}, %{id: 1})
    )

    #--------- When - Run the code under test
    # Make the HTTP request using Tesla
    # Mimic a use case where we create a user
    assert :ok = create_user!(%{username: "johndoe"})

    #--------- Then - Assert postconditions
    # Verify that the HTTP request was made and matches the expected parameters
    Tesla.Test.assert_received_tesla_call(env, [])
    Tesla.Test.assert_tesla_env(env, %Tesla.Env{
      method: :post,
      url: "https://acme.com/users",
      body: %{username: "johndoe"},
      status: 200,
    })

    # Verify that the mailbox is empty, indicating no additional requests were
    # made and all messages have been processed
    Tesla.Test.assert_tesla_empty_mailbox()
  end

  defp create_user!(body) do
    # ...
    Tesla.post!("https://acme.com/users", body)
    # ...
    :ok
  end
end
```

## 4. Run Your Tests

When you run your tests with `mix test`, all HTTP requests made by Tesla will
be intercepted by `MyApp.MockAdapter`, and responses will be provided based
on your `Mox` expectations.
