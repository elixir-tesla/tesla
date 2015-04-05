defmodule TeslaTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla.Builder

    adapter fn (_) ->
      {200, %{'Content-Type' => 'text/plain'}, "hello"}
    end
  end

  test "return :status 200" do
    assert Client.get("/").status == 200
  end

  test "return content type header" do
    assert Client.get("/").headers == %{'Content-Type' => 'text/plain'}
  end

  test "return 'hello' as body" do
    assert Client.get("/").body == "hello"
  end

  test "GET request" do
    assert Client.get("/").method == :get
  end

  test "HEAD request" do
    assert Client.head("/").method == :head
  end

  test "POST request" do
    assert Client.post("/", "").method == :post
  end

  test "PUT request" do
    assert Client.put("/", "").method == :put
  end

  test "PATCH request" do
    assert Client.patch("/", "").method == :patch
  end

  test "DELETE request" do
    assert Client.delete("/").method == :delete
  end

  test "TRACE request" do
    assert Client.trace("/").method == :trace
  end

  test "OPTIONS request" do
    assert Client.options("/").method == :options
  end

  test "insert request middleware function at runtime" do
    fun = fn (env, run) ->
      run.(%{env | url: env.url <> ".json"})
    end

    res = fun |> Client.get("/foo")
    assert res.url == "/foo.json"
  end

  test "insert response middleware function at runtime" do
    fun = fn (env, run) ->
      env = run.(env)
      %{env | body: env.body <> env.body}
    end

    res = fun |> Client.get("/foo")
    assert res.body == "hellohello"
  end
end

defmodule MiddlewareTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla.Builder

    with Tesla.Middleware.BaseUrl, "http://example.com"

    adapter fn (env) ->
      cond do
        List.last(String.split(env.url, "/")) == "secret" ->
          {200, %{}, env.headers['Authorization']}
        true ->
          {200, %{'Content-Type' => 'text/plain'}, "hello"}
      end
    end

    def new(token) do
      Tesla.build_client [
        {Tesla.Middleware.Headers, %{'Authorization' => "token: " <> token }}
      ]
    end
  end

  test "make use of base url" do
    assert Client.get("/").url == "http://example.com/"
  end

  test "build client" do
    c = Client.new("xxyyzz")
    res = c |> Client.get("/secret")
    assert res.body == "token: xxyyzz"
  end
end
