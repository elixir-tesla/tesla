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

Start with the operation-owned value module for `in: "path"` request values.
The final operation module will pass this map to `Tesla.Middleware.PathParams`
in `:modern` mode:

```elixir
defmodule MyApi.Operation.GetItem.Path do
  @type t :: %__MODULE__{
          id: integer(),
          coords: [String.t()]
        }

  defstruct [:id, :coords]

  def to_path_params(%__MODULE__{} = path) do
    %{
      "id" => path.id,
      "coords" => path.coords
    }
  end
end
```

The static OpenAPI path metadata for those names will use `Tesla.PathParam`,
`Tesla.PathParams`, and `Tesla.PathTemplate` when the operation module is built.

## Build the query module

Start with the operation-owned value module for `in: "query"` request values.
The final operation module will pass this map to `Tesla.Middleware.Query` in
`:modern` mode:

```elixir
defmodule MyApi.Operation.GetItem.Query do
  @type t :: %__MODULE__{
          :"$additional" => map() | nil,
          color: [String.t()],
          filter: keyword()
        }

  defstruct color: nil, filter: nil, "$additional": %{}

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

`Tesla.QueryParam` supports the OpenAPI query styles `:form`,
`:space_delimited`, `:pipe_delimited`, and `:deep_object`. Omit optional query
parameters from the returned map when they should not be sent. The static
OpenAPI query metadata for those names will use `Tesla.QueryParam` and
`Tesla.QueryParams` when the operation module is built.

Other top-level query params can share the same request query map and remain
normal Tesla query params. This example keeps those values in a generated
`:"$additional"` field.

## Build the header module

For `in: "header"`, convert `Tesla.HeaderParam` structs to the raw header
tuples accepted by Tesla:

```elixir
defmodule MyApi.Operation.GetItem.Header do
  alias Tesla.HeaderParam

  @type t :: %__MODULE__{
          request_id: String.t()
        }

  defstruct [:request_id]

  def to_headers(nil), do: []

  def to_headers(%__MODULE__{} = headers) do
    [
      HeaderParam.to_header(HeaderParam.new!("X-Request-ID", headers.request_id))
    ]
  end
end
```

`Tesla.HeaderParam` supports the OpenAPI header style `:simple`.

## Build the cookie module

For `in: "cookie"`, convert one or more `Tesla.CookieParam` structs into a
single `Cookie` header:

```elixir
defmodule MyApi.Operation.GetItem.Cookie do
  alias Tesla.CookieParam

  @type t :: %__MODULE__{
          session_id: String.t()
        }

  defstruct [:session_id]

  def to_headers(nil), do: []

  def to_headers(%__MODULE__{} = cookies) do
    [
      CookieParam.to_header([
        CookieParam.new!("session_id", cookies.session_id)
      ])
    ]
  end
end
```

`Tesla.CookieParam` supports the OpenAPI cookie styles `:form` and `:cookie`.

## Build the response wrapper

Generated clients can wrap `Tesla.Env` with the status, headers, and typed
body returned by each operation:

```elixir
defmodule MyApi.Response do
  @moduledoc """
  HTTP response wrapper with status, headers, and typed body.

  The `ok` field is `true` for 2xx status codes (200-299).
  """

  @type headers() :: [{String.t(), String.t()}]

  @type t(body_type, header_type) :: %__MODULE__{
          status: integer(),
          ok: boolean(),
          headers: header_type,
          body: body_type
        }

  defstruct status: nil, ok: nil, headers: nil, body: nil

  @doc false
  def new(%Tesla.Env{} = env, body) do
    %__MODULE__{
      status: env.status,
      ok: env.status >= 200 and env.status <= 299,
      headers: env.headers,
      body: body
    }
  end
end
```

## Build the operation module

Now assemble the nested modules into the generated operation. Static path
metadata and request private data stay on the operation module with
`Tesla.PathTemplate`, `Tesla.PathParam`, and `Tesla.PathParams`:

```elixir
defmodule MyApi.Operation.GetItem do
  alias MyApi.Client
  alias MyApi.Operation.GetItem.{Cookie, Header, Path, Query}
  alias MyApi.Response
  alias Tesla.{PathParam, PathParams, PathTemplate, QueryParam, QueryParams}

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
  @type result() :: {:ok, resp_200()} | {:error, term()}

  @path_template PathTemplate.new!("/items/{id}{coords}")

  @path_params PathParams.new!([
                 PathParam.new!("id"),
                 PathParam.new!("coords", style: :matrix, explode: true)
               ])

  @query_params QueryParams.new!([
                  QueryParam.new!("color", style: :pipe_delimited),
                  QueryParam.new!("filter", style: :deep_object)
                ])

  @private Tesla.Env.merge_private([
             PathTemplate.put_private(@path_template),
             PathParams.put_private(@path_params),
             QueryParams.put_private(@query_params)
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
    headers = Header.to_headers(operation.headers) ++ Cookie.to_headers(operation.cookies)

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
pass `Tesla.PathParams` through request private data. Use
`Tesla.Middleware.Query` in `:modern` mode when generated operations pass
`Tesla.QueryParams` through request private data:

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
- [OpenAPI Parameter Locations](https://spec.openapis.org/oas/latest.html#parameter-locations)
- [OpenAPI Style Values](https://spec.openapis.org/oas/latest.html#style-values)
- [OpenAPI Style Examples](https://spec.openapis.org/oas/latest.html#style-examples)
