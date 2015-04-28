defmodule TeslaTest do
  use ExUnit.Case

  defmodule ClientWithAdapterFun do
    use Tesla.Builder

    adapter fn (_) ->
      {201, %{}, "function adapter"}
    end
  end

  defmodule ModuleAdapter do
    def call(env) do
      %{env | status: 202}
    end
  end

  defmodule ClientWithAdapterMod do
    use Tesla.Builder

    adapter ModuleAdapter
  end

  test "client with adapter as function" do
    assert ClientWithAdapterFun.get("/").status == 201
  end

  test "client with adapter as module" do
    assert ClientWithAdapterMod.get("/").status == 202
  end



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

  test "path + query" do
    assert Client.get("/foo", %{a: 1, b: "foo"}).url == "/foo?a=1&b=foo"
  end

  test "path with query + query" do
    assert Client.get("/foo?c=4", %{a: 1, b: "foo"}).url == "/foo?c=4&a=1&b=foo"
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

defmodule ClientWrapTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla.Builder

    adapter fn (_env) ->
      {200, %{'Content-Type' => 'text/plain'}, "hello"}
    end

    defwrap custom_simple_get(a,b,c) do
      get("/#{a}/#{b}/#{c}")
    end

    defwrap custom_complex_get_head(a,b) do
      c = "#{b}-#{a}"
      head("/#{a}-#{b}").url <> " | " <> get("/#{c}").url
    end

    # defwrap custom_post_with_defaults(opts \\ []) do
    #   post("/" <> opts[:arg], "nothing")
    # end

    def new(token) do
      Tesla.build_client [
        {Tesla.Middleware.BaseUrl, "http://example.com"},
        {Tesla.Middleware.Headers, %{"Authorization" => "token #{token}"}}
      ]
    end
  end

  test "custom_simple_get - static" do
    env = Client.custom_simple_get("x","y","z")
    assert env.url == "/x/y/z"
    assert env.method == :get
  end

  test "custom_simple_get - dynamic" do
    client = Client.new("abc")
    env = client |> Client.custom_simple_get("x","y","z")
    assert env.url == "http://example.com/x/y/z"
    assert env.method == :get
  end

  test "custom_complex_get_head - static" do
    res = Client.custom_complex_get_head("x","y")
    assert res == "/x-y | /y-x"
  end

  test "custom_complex_get_head - dynamic" do
    client = Client.new("abc")
    res = client |> Client.custom_complex_get_head("x","y")
    assert res == "http://example.com/x-y | http://example.com/y-x"
  end


  # test "custom_post_with_defaults - static" do
  #   env = Client.custom_post_with_defaults(arg: "foo")
  #   assert env.url == "/foo"
  #   assert env.method == :post
  # end

  # test "custom_post_with_defaults - dynamic" do
  #   client = Client.new("abc")
  #   env = client |> Client.custom_post_with_defaults(arg: "foo")
  #   assert env.url == "http://example.com/foo"
  #   assert env.method == :post
  # end
end
