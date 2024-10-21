# Tesla

[![Test](https://github.com/elixir-tesla/tesla/actions/workflows/test.yml/badge.svg)](https://github.com/elixir-tesla/tesla/actions/workflows/test.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/tesla.svg)](https://hex.pm/packages/tesla)
[![Hexdocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/tesla/)
[![Hex.pm](https://img.shields.io/hexpm/dt/tesla.svg)](https://hex.pm/packages/tesla)
[![Hex.pm](https://img.shields.io/hexpm/dw/tesla.svg)](https://hex.pm/packages/tesla)
[![codecov](https://codecov.io/gh/elixir-tesla/tesla/branch/master/graph/badge.svg)](https://codecov.io/gh/elixir-tesla/tesla)

`Tesla` is an HTTP client that leverages middleware to streamline HTTP requests
and responses over a common interface for various adapters.

It simplifies HTTP communication by providing a flexible and composable
middleware stack. Developers can easily build custom API clients by stacking
middleware components that handle tasks like authentication, logging, and
retries. `Tesla` supports multiple HTTP adapters such as `Mint`, `Finch`,
`Hackney`, etc.

`Tesla` is ideal for developers who need a flexible and efficient HTTP client.
Its ability to swap out HTTP adapters and create custom middleware pipelines
empowers you to make different architectural decisions and build tools tailored
to your application's needs with minimal effort.

Inspired by [Faraday](https://github.com/lostisland/faraday) from Ruby.

## Getting started

Add `:tesla` as dependency in `mix.exs`:

```elixir
defp deps do
  [
     # or latest version
    {:tesla, "~> 1.11"},
    # optional, required by JSON middleware
    {:jason, "~> 1.4"},
    # optional, required by Mint adapter, recommended
    {:mint, "~> 1.0"}
  ]
end
```

> #### :httpc as default Adapter {: .error}
> The default adapter is erlang's built-in `httpc`, primarily to avoid
> additional
> dependencies when using `Tesla` in a new project. But it is not recommended to
> use it in production environment as it does not validate SSL certificates
> [among other issues](https://github.com/elixir-tesla/tesla/issues?utf8=%E2%9C%93&q=is%3Aissue+label%3Ahttpc+).
> Instead, consider using `Mint`, `Finch`, or `Hackney` adapters.
> We believe that such security issues should be addressed by `:httpc` itself
> and we are not planning to fix them in `Tesla` due to backward compatibility.

Configure default adapter in `config/config.exs`.

```elixir
# config/config.exs

# Make sure to install `mint` package as well, recommended
config :tesla, adapter: Tesla.Adapter.Mint
```

To make a simple GET request, run `iex -S mix` and execute:

    iex> Tesla.get!("https://httpbin.org/get").status
    # => 200

That will not include any middleware and will use the global default adapter.
Create a client to compose middleware and reuse it across requests.

    iex> client = Tesla.client([
    ...>  {Tesla.Middleware.BaseUrl, "https://httpbin.org/"},
    ...>  Tesla.Middleware.JSON,
    ...> ])

    iex> Tesla.get!(client, "/json").body
    # => %{"slideshow" => ...}

Lastly, you can enforce the adapter to be used by a specific client:

    iex> client = Tesla.client([], {Tesla.Adapter.Hackney, pool: :my_pool})

Happy hacking!

## What to do next?

Check out the following sections to learn more about `Tesla`:

### Explanations

- [Client](./guides/explanations/0.client.md)
- [Testing](./guides/explanations/1.testing.md)
- [Middleware](./guides/explanations/2.middleware.md)
- [Adapter](./guides/explanations/3.adapter.md)

### Howtos

#### Migrations

- [Migrating from v0 to v1.x](./guides/howtos/migrations/v0-to-v1.md)

### References

- [General Cheatsheet](./guides/cheatsheets/general.cheatmd)
- [Cookbook](https://github.com/elixir-tesla/tesla/wiki)

#### Middleware

`Tesla` is built around the concept of composable middlewares.

- `Tesla.Middleware.BaseUrl` - set base URL.
- `Tesla.Middleware.Headers` - set request headers.
- `Tesla.Middleware.Query` - set query parameters.
- `Tesla.Middleware.Opts` - set request options.
- `Tesla.Middleware.FollowRedirects` - follow HTTP 3xx redirects.
- `Tesla.Middleware.MethodOverride` - set `X-Http-Method-Override` header.
- `Tesla.Middleware.Logger` - log requests (method, url, status, and time).
- `Tesla.Middleware.KeepRequest` - keep request `body` and `headers`.
- `Tesla.Middleware.PathParams` - use templated URLs.

##### Formats

- `Tesla.Middleware.FormUrlencoded` - URL encode POST body, useful for POSTing a
  map/keyword list.
- `Tesla.Middleware.JSON` - encode/decode JSON request/response body.
- `Tesla.Middleware.Compression` - compress request/response body using
  `gzip` and `deflate`.
- `Tesla.Middleware.DecodeRels` - decode `Link` header into `opts[:rels]` field
  in response.

##### Auth

- `Tesla.Middleware.BasicAuth` - HTTP Basic Auth.
- `Tesla.Middleware.BearerAuth` - HTTP Bearer Auth.
- `Tesla.Middleware.DigestAuth`] - Digest access authentication.

##### Error handling

- `Tesla.Middleware.Timeout` - timeout request after X milliseconds despite of
  server response.
- `Tesla.Middleware.Retry` - retry few times in case of connection refused.
- `Tesla.Middleware.Fuse` - fuse circuit breaker integration.

#### Adapters

Tesla supports multiple HTTP adapter that do the actual HTTP request processing.

- `Tesla.Adapter.Httpc` - the default, built-in Erlang [httpc][0] adapter.
- `Tesla.Adapter.Hackney` - [hackney][1], simple HTTP client in Erlang.
- `Tesla.Adapter.Ibrowse` - [ibrowse][2], Erlang HTTP client.
- `Tesla.Adapter.Gun` - [gun][3], HTTP/1.1, HTTP/2 and Websocket client for
  Erlang/OTP.
- `Tesla.Adapter.Mint` - [mint][4], Functional HTTP client for Elixir with
  support for HTTP/1 and HTTP/2.
- `Tesla.Adapter.Finch` - [finch][5], An HTTP client with a focus on
  performance, built on top of [Mint][4] and [NimblePool][6].

## Sponsors

- [ubots - Ultimate Productivity Made Easy with Slack](https://ubots.co/)

[0]: https://erlang.org/doc/man/httpc.html
[1]: https://github.com/benoitc/hackney
[2]: https://github.com/cmullaparthi/ibrowse
[3]: https://github.com/ninenines/gun
[4]: https://github.com/elixir-mint/mint
[5]: https://github.com/keathley/finch
[6]: https://github.com/dashbitco/nimble_pool
