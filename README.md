# Tesla

[![Build Status](https://travis-ci.org/teamon/tesla.svg?branch=master)](https://travis-ci.org/teamon/tesla)
[![Hex.pm](https://img.shields.io/hexpm/v/tesla.svg)](http://hex.pm/packages/tesla)
[![Hex.pm](https://img.shields.io/hexpm/dt/tesla.svg)](https://hex.pm/packages/tesla)
[![Hex.pm](https://img.shields.io/hexpm/dw/tesla.svg)](https://hex.pm/packages/tesla)
[![codecov](https://codecov.io/gh/teamon/tesla/branch/master/graph/badge.svg)](https://codecov.io/gh/teamon/tesla)
[![Inline docs](http://inch-ci.org/github/teamon/tesla.svg)](http://inch-ci.org/github/teamon/tesla)

Tesla is an HTTP client loosely based on [Faraday](https://github.com/lostisland/faraday).
It embraces the concept of middleware when processing the request/response cycle.

> Note that this README refers to the `master` branch of Tesla, not the latest
  released version on Hex. See [the documentation](http://hexdocs.pm/tesla) for
  the documentation of the version you're using.

<hr/>
## [`0.x` to `1.0` Migration Guide](https://github.com/teamon/tesla/wiki/0.x-to-1.0-Migration-Guide)

```ex
defp deps do
  [{:tesla, github: "teamon/tesla", branch: "1.0"}]
end
```

<hr/>

## HTTP Client example

Define module with `use Tesla` and choose from a variety of middleware.

```elixir
defmodule GitHub do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://api.github.com"
  plug Tesla.Middleware.Headers, [{"authorization", "token xyz"}]
  plug Tesla.Middleware.JSON

  def user_repos(login) do
    get("/user/" <> login <> "/repos")
  end
end
```

Then use it like this:

```elixir
response = GitHub.user_repos("teamon")
response.status  # => 200
response.body    # => [%{…}, …]
response.headers # => [{"content-type", "application/json"}, ...]
```

See below for documentation.

## Installation

Add `tesla` as dependency in `mix.exs`

```elixir
defp deps do
  [{:tesla, "~> 0.10.0"},
   {:poison, ">= 1.0.0"}] # optional, required by JSON middleware
end
```

Also, unless using Elixir `>= 1.4`, add `:tesla` to the `applications` list:

```ex
def application do
  [applications: [:tesla, ...], ...]
end
```

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
- [Changelog](https://github.com/teamon/tesla/releases)


## Middleware
Tesla is built around the concept of composable middlewares.
This is very similar to how [Plug Router](https://github.com/elixir-plug/plug#the-plug-router) works.

#### Basic
- [`Tesla.Middleware.BaseUrl`](https://hexdocs.pm/tesla/Tesla.Middleware.BaseUrl.html) - set base url
- [`Tesla.Middleware.Headers`](https://hexdocs.pm/tesla/Tesla.Middleware.Headers.html) - set request headers
- [`Tesla.Middleware.Query`](https://hexdocs.pm/tesla/Tesla.Middleware.Query.html) - set query parameters
- [`Tesla.Middleware.Opts`](https://hexdocs.pm/tesla/Tesla.Middleware.Opts.html) - set request options
- [`Tesla.Middleware.FollowRedirects`](https://hexdocs.pm/tesla/Tesla.Middleware.FollowRedirects.html) - follow 3xx redirects
- [`Tesla.Middleware.MethodOverride`](https://hexdocs.pm/tesla/Tesla.Middleware.MethodOverride.html) - set X-Http-Method-Override
- [`Tesla.Middleware.Logger`](https://hexdocs.pm/tesla/Tesla.Middleware.Logger.html) - log requests (method, url, status, time)
- [`Tesla.Middleware.DebugLogger`](https://hexdocs.pm/tesla/Tesla.Middleware.DebugLogger.html) - log full requests & responses

#### Formats
- [`Tesla.Middleware.FormUrlencoded`](https://hexdocs.pm/tesla/Tesla.Middleware.FormUrlencoded.html) - urlencode POST body parameter, useful for POSTing a map/keyword list
- [`Tesla.Middleware.JSON`](https://hexdocs.pm/tesla/Tesla.Middleware.JSON.html) - JSON request/response body
- [`Tesla.Middleware.Compression`](https://hexdocs.pm/tesla/Tesla.Middleware.Compression.html) - gzip & deflate
- [`Tesla.Middleware.DecodeRels`](https://hexdocs.pm/tesla/Tesla.Middleware.DecodeRels.html) - decode `Link` header into `opts[:rels]` field in response

#### Auth
- [`Tesla.Middleware.BasicAuth`](https://hexdocs.pm/tesla/Tesla.Middleware.BasicAuth.html) - HTTP Basic Auth
- [`Tesla.Middleware.DigestAuth`](https://hexdocs.pm/tesla/Tesla.Middleware.DigestAuth.html) - Digest access authentication

#### Error handling
- [`Tesla.Middleware.Timeout`](https://hexdocs.pm/tesla/Tesla.Middleware.Timeout.html) - timeout request after X milliseconds despite of server response
- [`Tesla.Middleware.Retry`](https://hexdocs.pm/tesla/Tesla.Middleware.Retry.html) - retry few times in case of connection refused
- [`Tesla.Middleware.Fuse`](https://hexdocs.pm/tesla/Tesla.Middleware.Fuse.html) - fuse circuit breaker integration
- [`Tesla.Middleware.Tuples`](https://hexdocs.pm/tesla/Tesla.Middleware.Tuples.html) - return `{:ok, env} | {:error, reason}` instead of raising exception


## Runtime middleware

All HTTP functions (`get`, `post`, etc.) can take a dynamic client function as the first parameter.
This allow to use convenient syntax for modifying the behaviour in runtime.

Consider the following case: GitHub API can be accessed using OAuth token authorization.

We can't use `plug Tesla.Middleware.Headers, [{"authorization", "token here"}]`
since this would be compiled only once and there is no way to insert dynamic user token.

Instead, we can use `Tesla.build_client` to create a dynamic middleware function:

```elixir
defmodule GitHub do
  # same as above with a slightly change to `user_repos/1`

  def user_repos(client, login) do
    # pass `client` argument to `get` function
    get(client, "/user/" <> login <> "/repos")
  end

  def issues(client \\ %Tesla.Client{}) do
    # default to empty client that will not include runtime token
    get(client, "/issues")
  end

  # build dynamic client based on runtime arguments
  def client(token) do
    Tesla.build_client [
      {Tesla.Middleware.Headers, [{"authorization", "token: " <> token }]}
    ]
  end
end
```

and then:

```elixir
client = GitHub.client(user_token)
client |> GitHub.user_repos("teamon")
client |> GitHub.get("/me")

GitHub.issues()
client |> GitHub.issues()
```

The `Tesla.build_client` function can take two arguments: `pre` and `post` middleware.
The first list (`pre`) will be included before any other middleware. In case there is a need
to inject middleware at the end you can pass a second list (`post`). It will be put just
before adapter. In fact, one can even dynamically override the adapter.

For example, a private (per user) cache could be implemented as:

```elixir
def new(user) do
  Tesla.build_client [], [
    fn env, next ->
      case my_private_cache.fetch(user, env) do
        {:ok, env} -> env               # return cached response
        :error -> Tesla.run(env, next)  # make real request
      end
    end
  end
end
```


## Adapters

Tesla supports multiple HTTP adapter that do the actual HTTP request processing.

- [`Tesla.Adapter.Httpc`](https://hexdocs.pm/tesla/Tesla.Adapter.Httpc.html) - the default, built-in erlang [httpc](http://erlang.org/doc/man/httpc.html) adapter
- [`Tesla.Adapter.Hackney`](https://hexdocs.pm/tesla/Tesla.Adapter.Hackney.html) - [hackney](https://github.com/benoitc/hackney), "simple HTTP client in Erlang"
- [`Tesla.Adapter.Ibrowse`](https://hexdocs.pm/tesla/Tesla.Adapter.Ibrowse.html) - [ibrowse](https://github.com/cmullaparthi/ibrowse), "Erlang HTTP client"

When using ibrowse or hackney adapters remember to alter applications list in `mix.exs` (for Elixir < 1.4)

```elixir
def application do
  [applications: [:tesla, :ibrowse, ...], ...] # or :hackney
end
```

and add it to the dependency list

```elixir
defp deps do
  [{:tesla, "~> 0.7.0"},
   {:ibrowse, "~> 4.2"}, # or :hackney
   {:poison, ">= 1.0.0"}] # for JSON middleware
end
```


## Streaming

If adapter supports it, you can pass a [Stream](http://elixir-lang.org/docs/stable/elixir/Stream.html) as body, e.g.:

```elixir
defmodule ElasticSearch do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "http://localhost:9200"
  plug Tesla.Middleware.JSON

  def index(records_stream) do
    stream = records_stream |> Stream.map(fn record -> %{index: [some, data]})
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
  Multipart.new
  |> Multipart.add_content_type_param("charset=utf-8")
  |> Multipart.add_field("field1", "foo")
  |> Multipart.add_field("field2", "bar", headers: [{:"Content-Id", 1}, {:"Content-Type", "text/plain"}])
  |> Multipart.add_file("test/tesla/multipart_test_file.sh")
  |> Multipart.add_file("test/tesla/multipart_test_file.sh", name: "foobar")
  |> Multipart.add_file_content("sample file content", "sample.txt")

response = MyApiClient.post("http://httpbin.org/post", mp)
```


## Testing

You can set the adapter to `Tesla.Mock` in tests.

```elixir
# config/test.exs
# Use mock adapter for all clients
config :tesla, adapter: Tesla.Mock
# or only for one
config :tesla, MyClient, adapter: Tesla.Mock
```

Then, mock requests before using your client:


```elixir
defmodule MyAppTest do
  use ExUnit.Case

  setup do
    Tesla.Mock.mock fn
      %{method: :get, url: "http://example.com/hello"} ->
        %Tesla.Env{status: 200, body: "hello"}
      %{method: :post, url: "http://example.com/world"} ->
        %Tesla.Env{status: 200, body: "hi!"}
    end

    :ok
  end

  test "list things" do
    assert %Tesla.Env{} = env = MyApp.get("/hello")
    assert env.status == 200
    assert env.body == "hello"
  end
end
```


## Writing middleware

A Tesla middleware is a module with `call/3` function, that at some point calls `Tesla.run(env, next)` to process
the rest of stack.

```elixir
defmodule MyMiddleware do
  @behaviour Tesla.Middleware

  def call(env, next, options) do
    env
    |> do_something_with_request
    |> Tesla.run(next)
    |> do_something_with_response
  end
end
```

The arguments are:
- `env` - `Tesla.Env` instance
- `next` - middleware continuation stack; to be executed with `Tesla.run(env, next)`
- `options` - arguments passed during middleware configuration (`plug MyMiddleware, options`)

There is no distinction between request and response middleware, it's all about executing `Tesla.run/2` function at the correct time.

For example, a request logger middleware could be implemented like this:

```elixir
defmodule Tesla.Middleware.RequestLogger do
  @behaviour Tesla.Middleware

  def call(env, next, _) do
    IO.inspect env # print request env
    Tesla.run(env, next)
  end
end
```

and response logger middleware like this:

```elixir
defmodule Tesla.Middleware.ResponseLogger do
  @behaviour Tesla.Middleware

  def call(env, next, _) do
    res = Tesla.run(env, next)
    IO.inspect res # print response env
    res
  end
end
```

See [built-in middlewares](https://github.com/teamon/tesla/tree/master/lib/tesla/middleware) for more examples.

Middleware should have documentation following this template:

````elixir
defmodule Tesla.Middleware.SomeMiddleware do
  @behaviour Tesla.Middleware

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
end
````


## Direct usage

You can also use Tesla directly, without creating a client module.
This however won’t include any middleware.

```elixir
# Example get request
response = Tesla.get("http://httpbin.org/ip")
response.status   # => 200
response.body     # => "{\n  "origin": "87.205.72.203"\n}\n"
response.headers  # => [{"Content-Type", "application/json" ...}]


response = Tesla.get("http://httpbin.org/get", query: [a: 1, b: "foo"])
response.url     # => "http://httpbin.org/get?a=1&b=foo"


# Example post request
response = Tesla.post("http://httpbin.org/post", "data", headers: [{"Content-Type", "application/json"}])
```


## Cheatsheet


#### Making requests 101
```elixir
# GET /path
get("/path")

# GET /path?a=hi&b[]=1&b[]=2&b[]=3
get("/path", query: [a: "hi", b: [1,2,3]])

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

#### Configuring HTTP functions visibility
```elixir
# generate only get and post function
use Tesla, only: ~w(get post)a

# generate only delete fuction
use Tesla, only: [:delete]

# generate all functions except delete and options
use Tesla, except: [:delete, :options]
```

#### Disable docs for HTTP functions
```elixir
use Tesla, docs: false
```

#### Decode only JSON response (do not encode request)
```elixir
plug Tesla.Middleware.DecodeJson
```

#### Use other JSON library
```elixir
# use JSX
plug Tesla.Middleware.JSON, engine: JSX, engine_opts: [strict: [:comments]]

# use custom functions
plug Tesla.Middleware.JSON, decode: &JSX.decode/1, encode: &JSX.encode/1
```


#### Custom middleware
```elixir
defmodule Tesla.Middleware.MyCustomMiddleware do
  def call(env, next, options) do
    env
    |> do_something_with_request
    |> Tesla.run(next)
    |> do_something_with_response
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

Copyright (c) 2015-2017 [Tymon Tobolski](http://teamon.eu/about/)
