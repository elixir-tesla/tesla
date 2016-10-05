# Tesla

[![Build Status](https://travis-ci.org/teamon/tesla.svg?branch=master)](https://travis-ci.org/teamon/tesla)
[![Hex.pm](https://img.shields.io/hexpm/v/tesla.svg)](http://hex.pm/packages/tesla)

Tesla is an HTTP client losely based on [Faraday](https://github.com/lostisland/faraday).
It embraces the concept of middleware when processing the request/response cycle.

## Direct usage

```ex
# Example get request
response = Tesla.get("http://httpbin.org/ip")
response.status   # => 200
response.body     # => '{\n  "origin": "87.205.72.203"\n}\n'
response.headers  # => %{'Content-Type' => 'application/json' ...}


response = Tesla.get("http://httpbin.org/get", query: [a: 1, b: "foo"])
response.url     # => "http://httpbin.org/get?a=1&b=foo"


# Example post request
response = Tesla.post("http://httpbin.org/post", "data", headers: %{"Content-Type" => "application/json"})
```

## Installation

Add `tesla` as dependency in `mix.exs`

```ex
defp deps do
  [{:tesla, "~> 0.5.0"},
   {:poison, ">= 1.0.0"}] # for JSON middleware
end
```

### Adapters

When using `ibrowse` or `hackney` adapters remember to alter applications list in `mix.exs`

```ex
def application do
  [applications: [:ibrowse, ...], ...] # or :hackney
end
```

and add it to the dependency list

```ex
defp deps do
  [{:tesla, "~> 0.5.0"},
   {:ibrowse, "~> 4.2"}, # or :hackney
   {:poison, ">= 1.0.0"}] # for JSON middleware
end
```


## Creating API clients

Use `Tesla` module to create API wrappers.

For example

```ex
defmodule GitHub do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://api.github.com"
  plug Tesla.Middleware.Headers, %{"Authorization" => "token xyz"}
  plug Tesla.Middleware.JSON

  adapter Tesla.Adapter.Hackney

  def user_repos(login) do
    get("/user/" <> login <> "/repos")
  end
end
```

Then use it like this:

```ex
GitHub.get("/user/teamon/repos")
GitHub.user_repos("teamon")
```

## Adapters

Tesla has support for different adapters that do the actual HTTP request processing.

### [httpc](http://erlang.org/doc/man/httpc.html)

The default adapter, available in all erlang installations

### [hackney](https://github.com/benoitc/hackney)

This adapter supports real streaming body.
To use it simply include `adapter :hackney` line in your API client definition.
NOTE: Remember to include hackney in applications list.

### [ibrowse](https://github.com/cmullaparthi/ibrowse)

Tesla has built-in support for [ibrowse](https://github.com/cmullaparthi/ibrowse) Erlang HTTP client.
To use it simply include `adapter :ibrowse` line in your API client definition.
NOTE: Remember to include ibrowse in applications list.


### Test / Mock

When testing it might be useful to use simple function as adapter:

```ex
defmodule MyApi do
  use Tesla

  adapter fn (env) ->
    case env.url do
      "/"       -> %{env | status: 200, body: "home"}
      "/about"  -> %{env | status: 200, body: "about us"}
    end
  end
end
```


## Middleware

### Basic

- `Tesla.Middleware.BaseUrl` - set base url for all request
- `Tesla.Middleware.Headers` - set request headers
- `Tesla.Middleware.Query` - set query parameters
- `Tesla.Middleware.DecodeRels` - decode `Link` header into `opts[:rels]` field in response
- `Tesla.Middleware.Retry` - retry few times in case of connection refused

### JSON

NOTE: requires [poison](https://hex.pm/packages/poison) (or other engine) as dependency

- `Tesla.Middleware.JSON`` - encode/decode request/response bodies as JSON

If you are using different json library it can be easily configured:

```ex
plug Tesla.Middleware.JSON, engine: JSX, engine_opts: [strict: [:comments]]
# or
plug Tesla.Middleware.JSON, decode: &JSX.decode/1, encode: &JSX.encode/1
```


See [`json.ex`](https://github.com/teamon/tesla/blob/master/lib/tesla/middleware/json.ex) for implementation details.

### Logging

- `Tesla.Middleware.Logger` - log each request in single line including method, path, status and execution time (colored)
- `Tesla.Middleware.DebugLogger` - log full request and response (incl. headers and body)

### Authentication

- `Tesla.Middleware.DigestAuth` - [Digest access authentication](https://en.wikipedia.org/wiki/Digest_access_authentication)

## Dynamic middleware

All methods can take a middleware function as the first parameter.
This allow to use convenient syntax for modifying the behaviour in runtime.

Consider the following case: GitHub API can be accessed using OAuth token authorization.

We can't use `plug Tesla.Middleware.Headers, %{"Authorization" => "token here"}` since this would be compiled only once and there is no way to insert dynamic user token.

Instead, we can use `Tesla.build_client` to create a dynamic middleware function:

```ex
defmodule GitHub do
  # same as above

  def client(token) do
    Tesla.build_client [
      {Tesla.Middleware.Headers, %{"Authorization" => "token: " <> token }}
    ]
  end
end
```

and then:

```ex
client = GitHub.client(user_token)
client |> GitHub.user_repos("teamon")
client |> GitHub.get("/me")
```


## Writing your own middleware

A Tesla middleware is a module with `call/3` function, that at some point calls `Tesla.run(env, next)` to process
the rest of stack

```ex
defmodule MyMiddleware do
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

For example, z request logger middleware could be implemented like this:

```ex
defmodule Tesla.Middleware.RequestLogger do
  def call(env, next, _) do
    IO.inspect env # print request env
    Tesla.run(env, next)
  end
end
```

and response logger middleware like this:

```ex
defmodule Tesla.Middleware.ResponseLogger do
  def call(env, next, _) do
    res = Tesla.run(env, next)
    IO.inspect res # print response env
    res
  end
end
```

See [`core.ex`](https://github.com/teamon/tesla/blob/master/lib/tesla/middleware/core.ex) and [`json.ex`](https://github.com/teamon/tesla/blob/master/lib/tesla/middleware/json.ex) for more examples.


## Streaming body

If adapter supports it, you can pass a [Stream](http://elixir-lang.org/docs/stable/elixir/Stream.html) as body, e.g.:

```ex
defmodule ES do
  use Tesla.Builder

  plug Tesla.Middleware.BaseUrl, "http://localhost:9200"

  plug Tesla.Middleware.DecodeJson
  plug Tesla.Middleware.EncodeJson

  def index(records) do
    stream = records |> Stream.map(fn record -> %{index: [some, data]})
    post("/_bulk", stream)
  end
end
```

Each piece of stream will be encoded as json and sent as a new line (conforming to json stream format)
