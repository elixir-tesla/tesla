defmodule Tesla.Env do
  @moduledoc """
  This module defines a `t:Tesla.Env.t/0` struct that stores all data related to request/response.

  ## Fields

  - `:method` - method of request. Example: `:get`
  - `:url` - request url. Example: `"https://www.google.com"`
  - `:query` - structured query params. See `t:query/0`.
    Note: query params passed in url (e.g. `"/get?param=value"`) are not parsed to `query` field.
  - `:headers` - list of request/response headers.
    Example: `[{"content-type", "application/json"}]`.
    Note: request headers are overridden by response headers when adapter is called.
  - `:body` - request/response body.
    Note: request body is overridden by response body when adapter is called.
  - `:status` - response status. Example: `200`
  - `:opts` - list of options. Example: `[adapter: [recv_timeout: 30_000]]`
  - `:assigns` - a place for user data as a map. It can be used to carry application-specific
    metadata through the middleware pipeline.

  - `:private` - a map reserved for libraries and middleware to use. The keys must be atoms.
    Prefix the keys with the name of your project to avoid any future conflicts. The `tesla_`
    prefix is reserved for Tesla.
  """

  @type client :: Tesla.Client.t()
  @type method :: :head | :get | :delete | :trace | :options | :post | :put | :patch

  @typedoc """
  Request URL or request target.

  Examples:

  - `"https://www.google.com"`
  - `"/users/1"` when used with `Tesla.Middleware.BaseUrl`

  Callers are expected to pass a valid, already-encoded value.
  Tesla leaves the URL untouched and does not validate or normalize malformed input.
  """
  @type url :: binary
  @type query_key :: binary | atom
  @type query_scalar :: String.Chars.t()
  @type query_scalar_list :: [query_scalar]
  @type query_pair :: {query_key, param}
  @type query_list :: [query_pair]
  @type param :: query_scalar | query_scalar_list | query_list | %{optional(query_key) => param}

  @typedoc """
  Structured query params as a list or map, including nested maps.

  ## Examples

  - `[{"param", "value"}]` will be translated to `?param=value`.
  - `%{filters: %{page: 1}}` will be translated to `?filters%5Bpage%5D=1`
    (that is, `filters[page]` with brackets percent-encoded by default).

  Map query params do not guarantee encoded parameter order. Pass an ordered list
  of pairs if the exact query string order matters.
  """
  @type query :: [query_pair] | %{optional(query_key) => param}
  @type headers :: [{binary, binary}]

  @type body :: any
  @type status :: integer | nil
  @type opts :: keyword

  @type runtime :: {atom, atom, any} | {atom, atom} | {:fn, (t -> t)} | {:fn, (t, stack -> t)}
  @type stack :: [runtime]
  @type result :: {:ok, t()} | {:error, any}

  @type assigns :: %{optional(atom) => any}
  @type private :: %{optional(atom) => any}

  @type t :: %__MODULE__{
          method: method,
          query: query,
          url: url,
          headers: headers,
          body: body,
          status: status,
          opts: opts,
          assigns: assigns,
          private: private,
          __module__: atom() | nil,
          __client__: client() | nil
        }

  defstruct method: nil,
            url: "",
            query: [],
            headers: [],
            body: nil,
            status: nil,
            opts: [],
            assigns: %{},
            private: %{},
            __module__: nil,
            __client__: nil
end
