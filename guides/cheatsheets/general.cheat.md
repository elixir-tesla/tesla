# Basic Cheat Sheet

## Making Requests 101

### Creating a client

```elixir
client = Tesla.client([{Tesla.Middleware.BaseUrl, "https://httpbin.org"}])
Tesla.get(client, "/path")
```

### All Methods

```elixir
Tesla.get("https://httpbin.org/get")

Tesla.head("https://httpbin.org/anything")
Tesla.options("https://httpbin.org/anything")
Tesla.trace("https://httpbin.org/anything")

Tesla.post("https://httpbin.org/post", "body")
Tesla.put("https://httpbin.org/put", "body")
Tesla.patch("https://httpbin.org/patch", "body")
Tesla.delete("https://httpbin.org/anything")
```

### Query Params

```elixir
# GET /path?a=hi&b[]=1&b[]=2&b[]=3
Tesla.get("https://httpbin.org/anything", query: [a: "hi", b: [1, 2, 3]])
```

### Request Headers

```elixir
Tesla.get("https://httpbin.org/headers", headers: [{"x-api-key", "1"}])
```

### Client Default Headers

```elixir
client = Tesla.client([{Tesla.Middleware.Headers, [{"user-agent", "Tesla"}]}])
```

### Multipart

You can pass a `Tesla.Multipart` struct as the body:

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

{:ok, response} = Tesla.post("https://httpbin.org/post", mp)
```

## Streaming

### Streaming Request Body

If adapter supports it, you can pass a [Stream](https://hexdocs.pm/elixir/main/Stream.html)
as request body, e.g.:

```elixir
defmodule ElasticSearch do
  def index(records_stream) do
    stream = Stream.map(records_stream, fn record -> %{index: [some, data]} end)
    Tesla.post(client(), "/_bulk", stream)
  end

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, "http://localhost:9200"},
      Tesla.Middleware.JSON
    ], {Tesla.Adapter.Finch, name: MyFinch})
  end
end
```

### Streaming Response Body

If adapter supports it, you can pass a `response: :stream` option to return
response body as a [Stream](https://hexdocs.pm/elixir/main/Stream.html)

```elixir
defmodule OpenAI do
  def client(token) do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://api.openai.com/v1"},
      {Tesla.Middleware.BearerAuth, token: token},
      {Tesla.Middleware.JSON, decode_content_types: ["text/event-stream"]},
      {Tesla.Middleware.SSE, only: :data}
    ]
    Tesla.client(middleware, {Tesla.Adapter.Finch, name: MyFinch})
  end

  def completion(client, prompt) do
    data = %{
      model: "gpt-3.5-turbo",
      messages: [%{role: "user", content: prompt}],
      stream: true
    }
    Tesla.post(client, "/chat/completions", data, opts: [adapter: [response: :stream]])
  end
end

client = OpenAI.new("<token>")
{:ok, env} = OpenAI.completion(client, "What is the meaning of life?")
env.body |> Stream.each(fn chunk -> IO.inspect(chunk) end)
```

## Middleware

### Custom middleware

```elixir
defmodule Tesla.Middleware.MyCustomMiddleware do
  @moduledoc """
  Short description what it does

  Longer description, including e.g. additional dependencies.

  ### Options

  - `:list` - all possible options
  - `:with` - their default values

  ### Examples

      client = Tesla.client([{Tesla.Middleware.MyCustomMiddleware, with: value}])
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, options) do
    with %Tesla.Env{} = env <- preprocess(env) do
      env
      |> Tesla.run(next)
      |> postprocess()
    end
  end

  defp preprocess(env) do
    env
  end

  defp postprocess({:ok, env}) do
    {:ok, env}
  end

  def postprocess({:error, reason}) do
    {:error, reason}
  end
end
```

## Adapter

### Custom adapter

```elixir
defmodule Tesla.Adapter.MyCustomAdapter do
  @behaviour Tesla.Adapter

  @impl Tesla.Adapter
  def run(env, opts) do
    # do something
  end
end
```
