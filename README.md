# Tesla

[![Build Status](https://github.com/teamon/tesla/workflows/Test/badge.svg)](https://github.com/teamon/tesla/actions)
[![Hex.pm](https://img.shields.io/hexpm/v/tesla.svg)](http://hex.pm/packages/tesla)
[![Hex.pm](https://img.shields.io/hexpm/dt/tesla.svg)](https://hex.pm/packages/tesla)
[![Hex.pm](https://img.shields.io/hexpm/dw/tesla.svg)](https://hex.pm/packages/tesla)
[![codecov](https://codecov.io/gh/teamon/tesla/branch/master/graph/badge.svg)](https://codecov.io/gh/teamon/tesla)
[![Inline docs](https://inch-ci.org/github/teamon/tesla.svg)](http://inch-ci.org/github/teamon/tesla)

Tesla is an HTTP client loosely based on [Faraday](https://github.com/lostisland/faraday).
It embraces the concept of middleware when processing the request/response cycle.

> Note that this README refers to the `master` branch of Tesla, not the latest
  released version on Hex. See [the documentation](http://hexdocs.pm/tesla) for
  the documentation of the version you're using.

---

## [`0.x` to `1.0` Migration Guide](https://github.com/teamon/tesla/wiki/0.x-to-1.0-Migration-Guide)

```elixir
defp deps do
  [{:tesla, "~> 1.3.0"}]
end
```

[Documentation for 0.x branch](https://github.com/teamon/tesla/tree/0.x)

---

## HTTP Client example

Define module with `use Tesla` and choose from a variety of middleware.

```elixir
defmodule GitHub do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://api.github.com"
  plug Tesla.Middleware.Headers, [{"authorization", "token xyz"}]
  plug Tesla.Middleware.JSON

  def user_repos(login) do
    get("/users/" <> login <> "/repos")
  end
end
```

Then use it like this:

```elixir
{:ok, response} = GitHub.user_repos("teamon")

response.status
# => 200

response.body
# => [%{…}, …]

response.headers
# => [{"content-type", "application/json"}, ...]
```

See below for documentation.

## Installation

Add `tesla` as dependency in `mix.exs`:

```elixir
defp deps do
  [
    {:tesla, "~> 1.3.0"},

    # optional, but recommended adapter
    {:hackney, "~> 1.15.2"},

    # optional, required by JSON middleware
    {:jason, ">= 1.0.0"}
  ]
end

```

Configure default adapter in `config/config.exs` (optional).

```elixir
# config/config.exs

config :tesla, adapter: Tesla.Adapter.Hackney
```

> The default adapter is erlang's built-in `httpc`, but it is not recommended
to use it in production environment as it does not validate SSL certificates
[among other issues](https://github.com/teamon/tesla/issues?utf8=%E2%9C%93&q=is%3Aissue+label%3Ahttpc+).

## Documentation

- [Middleware](#middleware)
- [Runtime middleware](#runtime-middleware)
- [Adapters](#adapters)
- [Streaming](#streaming)
- [Multipart](#multipart)
- [Testing](#testing)
- [Writing middleware](#writing-middleware)
- [Direct usage](#direct-usage)
- [Cheatsheet](#cheatsheet)
- [Cookbook](https://github.com/teamon/tesla/wiki)
- [Changelog](https://github.com/teamon/tesla/releases)

## Middleware

Tesla is built around the concept of composable middlewares.
This is very similar to how [Plug Router](https://github.com/elixir-plug/plug#the-plug-router) works.

### Basic

- [`Tesla.Middleware.BaseUrl`](https://hexdocs.pm/tesla/Tesla.Middleware.BaseUrl.html) - set base url
- [`Tesla.Middleware.Headers`](https://hexdocs.pm/tesla/Tesla.Middleware.Headers.html) - set request headers
- [`Tesla.Middleware.Query`](https://hexdocs.pm/tesla/Tesla.Middleware.Query.html) - set query parameters
- [`Tesla.Middleware.Opts`](https://hexdocs.pm/tesla/Tesla.Middleware.Opts.html) - set request options
- [`Tesla.Middleware.FollowRedirects`](https://hexdocs.pm/tesla/Tesla.Middleware.FollowRedirects.html) - follow 3xx redirects
- [`Tesla.Middleware.MethodOverride`](https://hexdocs.pm/tesla/Tesla.Middleware.MethodOverride.html) - set X-Http-Method-Override
- [`Tesla.Middleware.Logger`](https://hexdocs.pm/tesla/Tesla.Middleware.Logger.html) - log requests (method, url, status, time)
- [`Tesla.Middleware.KeepRequest`](https://hexdocs.pm/tesla/Tesla.Middleware.KeepRequest.html) - keep request body & headers
- [`Tesla.Middleware.PathParams`](https://hexdocs.pm/tesla/Tesla.Middleware.PathParams.html) - use templated URLs

### Formats

- [`Tesla.Middleware.FormUrlencoded`](https://hexdocs.pm/tesla/Tesla.Middleware.FormUrlencoded.html) - urlencode POST body, useful for POSTing a map/keyword list
- [`Tesla.Middleware.JSON`](https://hexdocs.pm/tesla/Tesla.Middleware.JSON.html) - JSON request/response body
- [`Tesla.Middleware.Compression`](https://hexdocs.pm/tesla/Tesla.Middleware.Compression.html) - gzip & deflate
- [`Tesla.Middleware.DecodeRels`](https://hexdocs.pm/tesla/Tesla.Middleware.DecodeRels.html) - decode `Link` header into `opts[:rels]` field in response

### Auth

- [`Tesla.Middleware.BasicAuth`](https://hexdocs.pm/tesla/Tesla.Middleware.BasicAuth.html) - HTTP Basic Auth
- [`Tesla.Middleware.DigestAuth`](https://hexdocs.pm/tesla/Tesla.Middleware.DigestAuth.html) - Digest access authentication

### Error handling

- [`Tesla.Middleware.Timeout`](https://hexdocs.pm/tesla/Tesla.Middleware.Timeout.html) - timeout request after X milliseconds despite of server response
- [`Tesla.Middleware.Retry`](https://hexdocs.pm/tesla/Tesla.Middleware.Retry.html) - retry few times in case of connection refused
- [`Tesla.Middleware.Fuse`](https://hexdocs.pm/tesla/Tesla.Middleware.Fuse.html) - fuse circuit breaker integration

## Runtime middleware

All HTTP functions (`get`, `post`, etc.) can take a dynamic client as the first argument.
This allow to use convenient syntax for modifying the behaviour in runtime.

Consider the following case: GitHub API can be accessed using OAuth token authorization.

We can't use `plug Tesla.Middleware.Headers, [{"authorization", "token here"}]`
since this would be compiled only once and there is no way to insert dynamic user token.

Instead, we can use `Tesla.client` to create a client with dynamic middleware:

```elixir
defmodule GitHub do
  # notice there is no `use Tesla`

  def user_repos(client, login) do
    # pass `client` argument to `Tesla.get` function
    Tesla.get(client, "/user/" <> login <> "/repos")
  end

  def issues(client) do
    Tesla.get(client, "/issues")
  end

  # build dynamic client based on runtime arguments
  def client(token) do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://api.github.com"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "token: " <> token }]}
    ]

    Tesla.client(middleware)
  end
end
```

and then:

```elixir
client = GitHub.client(user_token)
client |> GitHub.user_repos("teamon")
client |> GitHub.get("/me")
```

## Adapters

Tesla supports multiple HTTP adapter that do the actual HTTP request processing.

- [`Tesla.Adapter.Httpc`](https://hexdocs.pm/tesla/Tesla.Adapter.Httpc.html) - the default, built-in erlang [httpc](http://erlang.org/doc/man/httpc.html) adapter
- [`Tesla.Adapter.Hackney`](https://hexdocs.pm/tesla/Tesla.Adapter.Hackney.html) - [hackney](https://github.com/benoitc/hackney), "simple HTTP client in Erlang"
- [`Tesla.Adapter.Ibrowse`](https://hexdocs.pm/tesla/Tesla.Adapter.Ibrowse.html) - [ibrowse](https://github.com/cmullaparthi/ibrowse), "Erlang HTTP client"
- [`Tesla.Adapter.Gun`](https://hexdocs.pm/tesla/Tesla.Adapter.Gun.html) - [gun](https://github.com/ninenines/gun), "HTTP/1.1, HTTP/2 and Websocket client for Erlang/OTP"
- [`Tesla.Adapter.Mint`](https://hexdocs.pm/tesla/Tesla.Adapter.Mint.html) - [mint](https://github.com/elixir-mint/mint), "Functional HTTP client for Elixir with support for HTTP/1 and HTTP/2"

When using adapter other than httpc remember to add it to the dependencies list in `mix.exs`

```elixir
defp deps do
  [{:tesla, "~> 1.3.0"},
   {:jason, ">= 1.0.0"}, # optional, required by JSON middleware
   {:hackney, "~> 1.10"}] # or :gun etc.
end
```

### Adapter options

In case there is a need to pass specific adapter options you can do it in one of three ways:

Using `adapter` macro:

```elixir
defmodule GitHub do
  use Tesla

  adapter Tesla.Adapter.Hackney, recv_timeout: 30_000, ssl_options: [certfile: "certs/client.crt"]
end
```

Using `Tesla.client/2`:

```elixir
def new(...) do
  middleware = [...]
  adapter = {Tesla.Adapter.Hackney, [recv_timeout: 30_000]}
  Tesla.client(middleware, adapter)
end
```

Passing directly to `get`/`post`/etc.

```elixir
MyClient.get("/", opts: [adapter: [recv_timeout: 30_000]])
Tesla.get(client, "/", opts: [adapter: [recv_timeout: 30_000]])
```

## Streaming

If adapter supports it, you can pass a [Stream](http://elixir-lang.org/docs/stable/elixir/Stream.html) as body, e.g.:

```elixir
defmodule ElasticSearch do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "http://localhost:9200"
  plug Tesla.Middleware.JSON

  def index(records_stream) do
    stream = records_stream |> Stream.map(fn record -> %{index: [some, data]} end)
    post("/_bulk", stream)
  end
end
```

Each piece of stream will be encoded as JSON and sent as a new line (conforming to JSON stream format)

## Multipart

You can pass a `Tesla.Multipart` struct as the body.

```elixir
alias Tesla.Multipart

mp =
  Multipart.new()
  |> Multipart.add_content_type_param("charset=utf-8")
  |> Multipart.add_field("field1", "foo")
  |> Multipart.add_field("field2", "bar",
    headers: [{"content-id", "1"}, {"content-type", "text/plain"}]
  )
  |> Multipart.add_file("test/tesla/multipart_test_file.sh")
  |> Multipart.add_file("test/tesla/multipart_test_file.sh", name: "foobar")
  |> Multipart.add_file_content("sample file content", "sample.txt")

{:ok, response} = MyApiClient.post("http://httpbin.org/post", mp)
```

## Testing

You can set the adapter to `Tesla.Mock` in tests.

```elixir
# config/test.exs
# Use mock adapter for all clients
config :tesla, adapter: Tesla.Mock
# or only for one
config :tesla, MyApi, adapter: Tesla.Mock
```

Then, mock requests before using your client:

```elixir
defmodule MyAppTest do
  use ExUnit.Case

  import Tesla.Mock

  setup do
    mock(fn
      %{method: :get, url: "http://example.com/hello"} ->
        %Tesla.Env{status: 200, body: "hello"}

      %{method: :post, url: "http://example.com/world"} ->
        json(%{"my" => "data"})
    end)

    :ok
  end

  test "list things" do
    assert {:ok, %Tesla.Env{} = env} = MyApp.get("/hello")
    assert env.status == 200
    assert env.body == "hello"
  end
end
```

## Writing middleware

A Tesla middleware is a module with `c:Tesla.Middleware.call/3` function, that at some point calls `Tesla.run/2` with `env` and `next` to process
the rest of stack.

```elixir
defmodule MyMiddleware do
  @behaviour Tesla.Middleware

  def call(env, next, options) do
    env
    |> do_something_with_request()
    |> Tesla.run(next)
    |> do_something_with_response()
  end
end
```

The arguments are:

- `env` - `Tesla.Env` instance
- `next` - middleware continuation stack; to be executed with `Tesla.run/2` with `env` and `next`
- `options` - arguments passed during middleware configuration (`plug MyMiddleware, options`)

There is no distinction between request and response middleware, it's all about executing `Tesla.run/2` function at the correct time.

For example, a request logger middleware could be implemented like this:

```elixir
defmodule Tesla.Middleware.RequestLogger do
  @behaviour Tesla.Middleware

  def call(env, next, _) do
    env
    |> IO.inspect()
    |> Tesla.run(next)
  end
end
```

and response logger middleware like this:

```elixir
defmodule Tesla.Middleware.ResponseLogger do
  @behaviour Tesla.Middleware

  def call(env, next, _) do
    env
    |> Tesla.run(next)
    |> IO.inspect()
  end
end
```

See [built-in middlewares](https://github.com/teamon/tesla/tree/master/lib/tesla/middleware) for more examples.

Middleware should have documentation following this template:

````elixir
defmodule Tesla.Middleware.SomeMiddleware do
  @moduledoc """
  Short description what it does

  Longer description, including e.g. additional dependencies.


  ### Example usage

  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.SomeMiddleware, most: :common, options: "here"
  end
  ```

  ### Options

  - `:list` - all possible options
  - `:with` - their default values
  """

  @behaviour Tesla.Middleware
end
````

## Direct usage

You can also use Tesla directly, without creating a client module.
This however won’t include any middleware.

```elixir
# Example get request
{:ok, response} = Tesla.get("http://httpbin.org/ip")

response.status
# => 200

response.body
# => "{\n  "origin": "87.205.72.203"\n}\n"

response.headers
# => [{"content-type", "application/json" ...}]

{:ok, response} = Tesla.get("http://httpbin.org/get", query: [a: 1, b: "foo"])

response.url
# => "http://httpbin.org/get?a=1&b=foo"

# Example post request
{:ok, response} =
  Tesla.post("http://httpbin.org/post", "data", headers: [{"content-type", "application/json"}])
```

## Cheatsheet

### Making requests 101

```elixir
# GET /path
get("/path")

# GET /path?a=hi&b[]=1&b[]=2&b[]=3
get("/path", query: [a: "hi", b: [1, 2, 3]])

# GET with dynamic client
get(client, "/path")
get(client, "/path", query: [page: 3])

# arguments are the same for GET, HEAD, OPTIONS & TRACE
head("/path")
options("/path")
trace("/path")

# POST, PUT, PATCH
post("/path", "some-body-i-used-to-know")
put("/path", "some-body-i-used-to-know", query: [a: "0"])
patch("/path", multipart)
```

### Configuring HTTP functions visibility

```elixir
# generate only get and post function
use Tesla, only: ~w(get post)a

# generate only delete function
use Tesla, only: [:delete]

# generate all functions except delete and options
use Tesla, except: [:delete, :options]
```

### Disable docs for HTTP functions

```elixir
use Tesla, docs: false
```

### Decode only JSON response (do not encode request)

```elixir
plug Tesla.Middleware.DecodeJson
```

### Use other JSON library

```elixir
# use JSX
plug Tesla.Middleware.JSON, engine: JSX, engine_opts: [strict: [:comments]]

# use custom functions
plug Tesla.Middleware.JSON, decode: &JSX.decode/1, encode: &JSX.encode/1
```

### Custom middleware

```elixir
defmodule Tesla.Middleware.MyCustomMiddleware do
  def call(env, next, options) do
    env
    |> do_something_with_request()
    |> Tesla.run(next)
    |> do_something_with_response()
  end
end
```

## Contributing

1. Fork it (https://github.com/teamon/tesla/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

Copyright (c) 2015-2018 [Tymon Tobolski](http://teamon.eu/about/)
