# Migrate from v0 to v1

This is a list of all breaking changes.

Version `1.0` has been released, try it today!

```elixir
  defp deps do
    [
      {:tesla, "1.0.0"}
    ]
  end
```

Any other breaking change not on this list is considered a bug - in you find one please create a new issue.

## Returning Tuple Result from HTTP Functions

`get(..)`, `post(..)`, etc. now return `{:ok, Tesla.Env} | {:error, reason}` ([#177](https://github.com/elixir-tesla/tesla/issues/177))

In `0.x` all http functions returned either `Tesla.Env` or raised an error.
In `1.0` these functions return ok/error tuples. The old behaviour can be achieved with the new `! (bang)` functions: `get!(...)`, `post!(...)`, etc.

```elixir
case MyApi.get("/") do
  {:ok, %Tesla.Env{status: 200}} -> # ok response
  {:ok, %Tesla.Env{status: 500}} -> # server error
  {:error, reason} -> # connection & other errors
end
```

## Dropped aliases support ([#159](https://github.com/elixir-tesla/tesla/issues/159))

Use full module name for middleware and adapters.

```diff
# middleware
-  plug :json
+  plug Tesla.Middleware.JSON

# adapter
-  adapter :hackney
+  adapter Tesla.Adapter.Hackney

# config
-  config :tesla, adapter: :mock
+  config :tesla, adapter: Tesla.Mock
```

## Dropped local middleware/adapter functions ([#171](https://github.com/elixir-tesla/tesla/issues/171))

Extract functionality into separate module.

```diff
 defmodule MyClient do
-  plug :some_local_fun
-
-  def some_local_fun(env, next) do
     # implementation
-  end
 end

+defmodule ProperlyNamedMiddleware do
+  @behaviour Tesla.Middleware
+  def call(env, next, _opts) do
     # implementation
+  end
+end

 defmodule MyClient do
+  plug ProperlyNamedMiddleware
 end
```

## Dropped client as function ([#176](https://github.com/elixir-tesla/tesla/issues/176))

This is very unlikely, but... if you hacked around with custom functions as client (the first argument) you need to stop.
See `Tesla.client/2` instead.

## Headers are now a list ([#160](https://github.com/elixir-tesla/tesla/issues/160))

In `0.x` `env.headers` are a `map(binary => binary)`.

In `1.x` `env.headers` are a `[{binary, binary}]`.

This change also applies to middleware headers.

#### Setting a header

```diff
-  env
-  |> Map.update!(&Map.put(&1.headers, "name", "value"))

+  env
+  |> Tesla.put_header("name", "value")
```

#### Getting a header
```diff
-  env.headers["cookie"]
+  Tesla.get_header(env, "cookie") # => "secret"
+  Tesla.get_headers(env, "cookie") # => ["secret", "token", "and more"]


-  case env.headers do
-    %{"server" => server} -> ...
-    _ -> ...
-  end
+  case Tesla.get_header(env, "server") do
+    nil -> ...
+    server ->
+  end
```

There are five new functions to deal with headers:
- `Tesla.get_header(env, name) :: binary | nil` - Get first header with given `name`
- `Tesla.get_headers(env, name)` :: [binary] - Get all headers values with given `name`
- `Tesla.put_header(env, name, value)` - Set header with given `name` and `value`. Existing header with the same name will be overwritten.
- `Tesla.put_headers(env, list)` - Add headers to the end of `env.headers`. Does **not** make the headers unique.
- `Tesla.delete_header(env, name)` - Delete all headers with given `name`

## Dropped support for Elixir 1.3 ([#164](https://github.com/elixir-tesla/tesla/issues/164))
Tesla `1.0` works only with Elixir 1.4 or newer

## Adapter options need to be wrapped in `:adapter` key:

```diff
- MyClient.get("/", opts: [recv_timeout: 30_000])
+ MyClient.get("/", opts: [adapter: [recv_timeout: 30_000]])
```


## DebugLogger merged into Logger ([#150](https://github.com/elixir-tesla/tesla/issues/150))

Debugging request and response details has been merged into a single Logger middleware. See `Tesla.Middleware.Logger` documentation for more information.

```diff
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.Logger
-   plug Tesla.Middleware.DebugLogger
  end
```

## Jason is the new default JSON library ([#175](https://github.com/elixir-tesla/tesla/issues/175))

The `Tesla.Middleware.JSON` now requires [jason](https://github.com/michalmuskala/jason) by default. If you want to keep using poison you will have to set `:engine` option - see [documentation](https://hexdocs.pm/tesla/Tesla.Middleware.JSON.html#module-example-usage) for details.
