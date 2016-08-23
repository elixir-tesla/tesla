# Tesla

[![CircleCI Status](https://circleci.com/gh/teamon/tesla.png?style=shield)](https://circleci.com/gh/teamon/tesla)
[![Hex.pm](https://img.shields.io/hexpm/v/tesla.svg)](http://hex.pm/packages/tesla)

Tesla is an HTTP client losely based on [Faraday](https://github.com/lostisland/faraday).
It embraces the concept of middleware when processing the request/response cycle.

> **WARNING**: Tesla is currently under heavy development, so please don't use it in your production application just yet.

>  Nevertheless all comments/issues/suggestions are more than welcome - please submit them using [GitHub issues](https://github.com/teamon/tesla/issues), thanks!


## Basic usage

```ex
# Example get request
response = Tesla.get("http://httpbin.org/ip")
response.status   # => 200
response.body     # => '{\n  "origin": "87.205.72.203"\n}\n'
response.headers  # => %{'Content-Type' => 'application/json' ...}


response = Tesla.get({"http://httpbin.org/get", [a: 1, b: "foo"]})
response.url     # => "http://httpbin.org/get?a=1&b=foo"


# Example post request
response = Tesla.post("http://httpbin.org/post", "data")
```

## Installation

Add `tesla` as dependency in `mix.exs`

```ex
defp deps do
  [{:tesla, "~> 0.1.0"},
   {:exjsx, "~> 3.1.0"}] # for JSON middleware
end
```

When using `ibrowse` or `hackney` adapters remember to alter applications list in `mix.exs`

```ex
def application do
  [applications: [:ibrowse, ...], ...] # or :hackney
end
```


## Creating API clients

Use `Tesla.Builder` module to create API wrappers.

For example

```ex
defmodule GitHub do
  use Tesla.Builder

  plug Tesla.Middleware.BaseUrl, "https://api.github.com"
  plug Tesla.Middleware.Headers, %{'Authorization' => 'xyz'}
  plug Tesla.Middleware.EncodeJson
  plug Tesla.Middleware.DecodeJson

  adapter Tesla.Adapter.Ibrowse

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

### [ibrowse](https://github.com/cmullaparthi/ibrowse)

Tesla has built-in support for [ibrowse](https://github.com/cmullaparthi/ibrowse) Erlang HTTP client.
To use it simply include `adapter :ibrowse` line in your API client definition.
NOTE: Remember to include ibrowse in applications list.

### [hackney](https://github.com/benoitc/hackney)

This adapter supports real streaming body.
To use it simply include `adapter :hackney` line in your API client definition.
NOTE: Remember to include hackney in applications list.


### Test / Mock

When testing it might be useful to use simple function as adapter:

```ex
defmodule MyApi do
  use Tesla

  adapter fn (env) ->
    case env.url do
      "/"       -> {200, %{}, "home"}
      "/about"  -> {200, %{}, "about us"}
    end
  end
end
```


## Middleware

### Basic

- `Tesla.Middleware.BaseUrl` - set base url for all request
- `Tesla.Middleware.Headers` - set request headers
- `Tesla.Middleware.QueryParams` - set query parameters
- `Tesla.Middleware.AdapterOptions` - set default adapter options (like ssl etc.)
- `Tesla.Middleware.DecodeRels` - decode `Link` header into `rels` field in response

### JSON

NOTE: requires [poison](https://hex.pm/packages/poison) (or other engine) as dependency

- `Tesla.Middleware.DecodeJson` - decode response body as JSON
- `Tesla.Middleware.EncodeJson` - endode request body as JSON

If you are using different json library it can be easily configured:

```ex
plug Tesla.Middleware.DecodeJson, engine: JSX, opts: [labels: :atom]
# or
plug Tesla.Middleware.DecodeJson, decode: &JSX.decode/1
```


See [`json.ex`](https://github.com/teamon/tesla/blob/master/lib/tesla/middleware/json.ex) for implementation details.

### Logging

- `Tesla.Middleware.Logger` - log each request in single line including method, path, status and execution time (colored)
- `Tesla.Middleware.DebugLogger` - log full request and response (incl. headers and body)

## Dynamic middleware

All methods can take a middleware function as the first parameter.
This allow to use convinient syntax for modyfiyng the behaviour in runtime.

Consider the following case: GitHub API can be accessed using OAuth token authorization.

We can't use `plug Tesla.Middleware.Headers, %{'Authorization' => 'token here'}` since this would be compiled only once and there is no way to insert dynamic user token.

Instead, we can use `Tesla.build_client` to create a dynamic middleware function:

```ex
defmodule GitHub do
  # same as above

  def client(token) do
    Tesla.build_client [
      {Tesla.Middleware.Headers, %{'Authorization' => "token: " <> token }}
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

A Tesla middleware is a module with `call/3` function:

```ex
defmodule MyMiddleware do
  def call(env, run, options) do
    # ...
  end
end
```

The arguments are:
- `env` - `Tesla.Env` instance
- `run` - continuation function for the rest of middleware/adapter stack
- `options` - arguments passed during middleware configuration (`plug MyMiddleware, options`)

There is no distinction between request and response middleware, it's all about executing `run` function at the correct time.

For example, z request logger middleware could be implemented like this:

```ex
defmodule Tesla.Middleware.RequestLogger do
  def call(env, run, _) do
    IO.inspect env # print request env
    run.(env)
  end
end
```

and response logger middleware like this:

```ex
defmodule Tesla.Middleware.ResponseLogger do
  def call(env, run, _) do
    res = run.(env)
    IO.inspect res # print response env
    res
  end
end
```

See [`core.ex`](https://github.com/teamon/tesla/blob/master/lib/tesla/middleware/core.ex) and [`json.ex`](https://github.com/teamon/tesla/blob/master/lib/tesla/middleware/json.ex) for more examples.


## Asynchronous requests

If adapter supports it, you can make asynchronous requests by passing `respond_to: pid` option:

```ex

Tesla.get("http://example.org", respond_to: self)

receive do
  {:tesla_response, res} -> res.status # => 200
end
```

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
