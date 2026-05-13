# Working with OpenAPI parameters

Tesla does not parse OpenAPI documents or generate client modules. It provides
the request values and middleware needed for generated or hand-written clients
to represent OpenAPI parameter serialization.

## Start with the OpenAPI spec

This example operation has path, query, header, and cookie parameters:

```yaml
paths:
  /items/{id}{coords}:
    get:
      operationId: getItem
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: integer
        - name: coords
          in: path
          required: true
          style: matrix
          explode: true
          schema:
            type: array
            items:
              type: string
        - name: color
          in: query
          required: true
          style: pipeDelimited
          schema:
            type: array
            items:
              type: string
        - name: filter
          in: query
          required: true
          style: deepObject
          schema:
            type: object
        - name: X-Request-ID
          in: header
          required: true
          schema:
            type: string
        - name: session_id
          in: cookie
          required: true
          schema:
            type: string
      responses:
        "200":
          description: Item response
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/GetItemResponse"
```

## Build the path module

Start with the operation-owned module for `in: "path"` values and metadata.
The final operation module will store the result of `Path.path_params()` in a
module attribute and pass the request value map to `Tesla.Middleware.PathParams`
in `:modern` mode:

```elixir
defmodule MyApi.Operation.GetItem.Path do
  alias Tesla.OpenAPI.{PathParam, PathParams}

  @type t :: %__MODULE__{
          id: integer(),
          coords: [String.t()]
        }

  defstruct [:id, :coords]

  @path_params PathParams.new!([
                 PathParam.new!("id"),
                 PathParam.new!("coords", style: :matrix, explode: true)
               ])

  def path_params, do: @path_params

  def to_path_params(%__MODULE__{} = path) do
    %{
      "id" => path.id,
      "coords" => path.coords
    }
  end
end
```

The runtime struct contains request values only. `path_params/0` returns the
static OpenAPI path metadata that the operation module stores in a module
attribute.

## Build the query module

Start with the operation-owned module for `in: "query"` values and metadata.
The final operation module will store the result of `Query.query_params()` in a
module attribute and pass the request value map to `Tesla.Middleware.Query` in
`:modern` mode:

```elixir
defmodule MyApi.Operation.GetItem.Query do
  alias Tesla.OpenAPI.{QueryParam, QueryParams}

  @type t :: %__MODULE__{
          :"$additional" => map() | nil,
          color: [String.t()],
          filter: keyword()
        }

  defstruct color: nil, filter: nil, "$additional": %{}

  @query_params QueryParams.new!([
                  QueryParam.new!("color", style: :pipe_delimited),
                  QueryParam.new!("filter", style: :deep_object)
                ])

  def query_params, do: @query_params

  def to_query(nil), do: %{}

  def to_query(%__MODULE__{} = query) do
    additional = query."$additional" || %{}

    Map.merge(additional, %{
      "color" => query.color,
      "filter" => query.filter
    })
  end
end
```

`Tesla.OpenAPI.QueryParam` supports the OpenAPI query styles `:form`,
`:space_delimited`, `:pipe_delimited`, and `:deep_object`. Omit optional query
parameters from the returned map when they should not be sent. The operation
module uses the result of `Query.query_params()` when it builds its private
metadata.

Other top-level query params can share the same request query map and remain
normal Tesla query params. This example keeps those values in a generated
`:"$additional"` field.

## Build the header module

For `in: "header"`, expose `Tesla.OpenAPI.HeaderParam` metadata and convert the
request struct into the value map used by `Tesla.OpenAPI.HeaderParams`:

```elixir
defmodule MyApi.Operation.GetItem.Header do
  alias Tesla.OpenAPI.{HeaderParam, HeaderParams}

  @type t :: %__MODULE__{
          request_id: String.t()
        }

  defstruct [:request_id]

  @header_params HeaderParams.new!([
                   HeaderParam.new!("X-Request-ID")
                 ])

  def header_params, do: @header_params

  def to_header_params(nil), do: %{}

  def to_header_params(%__MODULE__{} = headers) do
    %{
      "X-Request-ID" => headers.request_id
    }
  end
end
```

`Tesla.OpenAPI.HeaderParam` supports the OpenAPI header style `:simple`.

## Build the cookie module

For `in: "cookie"`, expose `Tesla.OpenAPI.CookieParam` metadata and convert the
request struct into the value map used by `Tesla.OpenAPI.CookieParams`:

```elixir
defmodule MyApi.Operation.GetItem.Cookie do
  alias Tesla.OpenAPI.{CookieParam, CookieParams}

  @type t :: %__MODULE__{
          session_id: String.t()
        }

  defstruct [:session_id]

  @cookie_params CookieParams.new!([
                   CookieParam.new!("session_id")
                 ])

  def cookie_params, do: @cookie_params

  def to_cookie_params(nil), do: %{}

  def to_cookie_params(%__MODULE__{} = cookies) do
    %{
      "session_id" => cookies.session_id
    }
  end
end
```

`Tesla.OpenAPI.CookieParam` supports the OpenAPI cookie styles `:form` and `:cookie`.

## Build the response wrapper

Generated clients can wrap `Tesla.Env` with the status, headers, and typed
body returned by each operation:

```elixir
defmodule MyApi.Response do
  use Tesla.OpenAPI.Response
end
```

## Build the operation module

Now assemble the nested modules into the generated operation. The nested
modules expose each parameter collection, and the operation module uses those
results when it builds static request metadata:

```elixir
defmodule MyApi.Operation.GetItem do
  alias MyApi.Client
  alias MyApi.Operation.GetItem.{Cookie, Header, Path, Query}
  alias MyApi.Response
  alias Tesla.OpenAPI
  alias Tesla.OpenAPI.{CookieParams, HeaderParams, PathParams, PathTemplate, QueryParams}

  defstruct path: nil,
            query: nil,
            headers: nil,
            cookies: nil

  @type t :: %__MODULE__{
          path: Path.t() | nil,
          query: Query.t() | nil,
          headers: Header.t() | nil,
          cookies: Cookie.t() | nil
        }

  @type resp_body_200() :: MyApi.Schemas.GetItemResponse.t()
  @type resp_header_200() :: Response.headers()
  @type resp_200() :: Response.t(resp_body_200(), resp_header_200())
  @type resp_401() :: Response.t(nil, Response.headers())
  @type resp_404() :: Response.t(nil, Response.headers())
  @type result() :: {:ok, resp_200() | resp_401() | resp_404()} | {:error, term()}

  @path_template PathTemplate.new!("/items/{id}{coords}")
  @header_params Header.header_params()
  @cookie_params Cookie.cookie_params()

  @private OpenAPI.merge_private([
             PathTemplate.put_private(@path_template),
             PathParams.put_private(Path.path_params()),
             QueryParams.put_private(Query.query_params())
           ])

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      path: Map.fetch!(attrs, :path),
      query: Map.get(attrs, :query),
      headers: Map.get(attrs, :headers),
      cookies: Map.get(attrs, :cookies)
    }
  end

  @doc false
  def handle_operation(%Client{} = client, %__MODULE__{} = operation, opts) do
    headers =
      HeaderParams.to_headers(@header_params, Header.to_header_params(operation.headers)) ++
        CookieParams.to_headers(@cookie_params, Cookie.to_cookie_params(operation.cookies))

    request_opts = [
      method: :get,
      url: @path_template.path,
      query: Query.to_query(operation.query),
      headers: headers,
      opts: Keyword.put(opts, :path_params, Path.to_path_params(operation.path)),
      private: @private
    ]

    case Tesla.request(client.client, request_opts) do
      {:ok, %Tesla.Env{status: 200} = env} ->
        {:ok, Response.new(env, MyApi.Schemas.GetItemResponse.new(env.body))}

      {:ok, %Tesla.Env{status: status} = env} when status in [401, 404] ->
        {:ok, Response.new(env, nil)}

      {:ok, env} ->
        {:ok, Response.new(env, env.body)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

## Build the client stack

Use `Tesla.Middleware.PathParams` in `:modern` mode when generated operations
pass `Tesla.OpenAPI.PathParams` through `t:Tesla.Env.private/0`. Use
`Tesla.Middleware.Query` in `:modern` mode when generated operations pass
`Tesla.OpenAPI.QueryParams` through `t:Tesla.Env.private/0`:

```elixir
defmodule MyApi.Client do
  @type t :: %__MODULE__{
          client: Tesla.Client.t()
        }

  defstruct [:client]

  def new(opts) do
    middleware = [
      {Tesla.Middleware.BaseUrl, Keyword.fetch!(opts, :base_url)},
      {Tesla.Middleware.PathParams, mode: :modern},
      {Tesla.Middleware.Query, mode: :modern},
      Tesla.Middleware.JSON
    ]

    adapter = Keyword.fetch!(opts, :adapter)

    %__MODULE__{client: Tesla.client(middleware, adapter)}
  end
end
```

## Build the API module

Expose a generated function that delegates to the operation module:

```elixir
defmodule MyApi do
  alias MyApi.Client
  alias MyApi.Operation.GetItem

  @spec send_get_item(Client.t(), GetItem.t(), keyword()) :: GetItem.result()
  def send_get_item(%Client{} = client, %GetItem{} = operation, opts \\ []) do
    GetItem.handle_operation(client, operation, opts)
  end
end
```

## Send the operation

The caller builds operation values and sends them through the generated
API module:

```elixir
alias MyApi.Operation.GetItem
alias MyApi.Operation.GetItem.{Cookie, Header, Path, Query}

operation =
  GetItem.new(%{
    path: %Path{id: 42, coords: ["blue", "black"]},
    query: %Query{
      :"$additional" => %{"debug" => true},
      color: ["blue", "black"],
      filter: [role: "admin"]
    },
    headers: %Header{request_id: "req-123"},
    cookies: %Cookie{session_id: "abc123"}
  })

MyApi.send_get_item(client, operation, [])
```

## Further reading

- [OpenAPI in Tesla](../explanations/4.openapi.md)
- [OpenAPI Cheat Sheet](../cheatsheets/openapi.cheatmd)
- [OpenAPI Parameter Locations](https://spec.openapis.org/oas/latest.html#parameter-locations)
- [OpenAPI Style Values](https://spec.openapis.org/oas/latest.html#style-values)
- [OpenAPI Style Examples](https://spec.openapis.org/oas/latest.html#style-examples)
