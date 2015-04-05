Tesla
=====

## Basic usage

```ex
# Start underlying ibrowse default adapter
Tesla.start

# Example get request
response = Tesla.get("http://httpbin.org/ip")
response.status   # => 200
response.body     # => '{\n  "origin": "87.205.72.203"\n}\n'
response.headers  # => %{'Content-Type' => 'application/json' ...}

# Example post request
response = Tesla.post("http://httpbin.org/post", "data")
```

## Creating API clients

Use `Tesla.Builder` module to create API wrappers.

For example

```ex
defmodule GitHub do
  use Tesla.Builder

  with Tesla.Middleware.BaseUrl, "https://api.github.com"
  with Tesla.Middleware.Headers, %{'Authorization' => 'xyz'}
  with Tesla.Middleware.EncodeJson
  with Tesla.Middleware.DecodeJson

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

## Dynamic middleware

All methods can take a middleware function as the first parameter.
This allow to use convinient syntax for modyfiyng the behaviour in runtime.

Consider the following case: GitHub API can be accessed using OAuth token authorization.

We can't use `with Tesla.Middleware.Headers, %{'Authorization' => 'token here'}` since this would be compiled only once and there is no way to insert dynamic user token.

Instead, we can use `Tesla.build_client` to create a dynamid middleware function:

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


## Available Middleware

### Basic

- `Tesla.Middleware.BaseUrl` - set base url for all request
- `Tesla.Middleware.Headers` - set request headers

### JSON
NOTE: requires [exjsx](https://github.com/talentdeficit/exjsx) as dependency

- `Tesla.Middleware.DecodeJson` - decode response body as JSON
- `Tesla.Middleware.EncodeJson` - endode request body as JSON

If you are using different json library writing middleware should be straightforward. See [link to json.ex] for implementation.
