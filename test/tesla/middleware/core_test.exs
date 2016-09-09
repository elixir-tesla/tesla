defmodule CoreTest do
  use ExUnit.Case
  alias Tesla.Middleware.Normalize

  describe "middleware basics" do
    defmodule Opt do
      def call(env, next, key: key, value: value) do
        env
        |> Tesla.run(next)
        |> Tesla.put_opt(key, value)
      end
    end

    defmodule TestClient do
      use Tesla
      @api_key "some_key"

      plug Opt, key: :attr, value: %{"Authorization" => @api_key}
      plug Opt, key: :int,  value: 123
      plug Opt, key: :list, value: ["a", "b", "c"]
      plug Opt, key: :fun,  value: (fn x -> x*2 end)

      adapter fn env -> env end
    end

    test "apply middleware options" do
      env = TestClient.get("/")

      assert env.opts[:attr] == %{"Authorization" => "some_key"}
      assert env.opts[:int] == 123
      assert env.opts[:list] == ["a", "b", "c"]
      assert env.opts[:fun].(4) == 8
    end
  end

  describe "Tesla.Middleware.BaseUrl" do
    alias Tesla.Middleware.BaseUrl
    use Tesla.Middleware.TestCase, middleware: BaseUrl

    test "base without slash, path without slash" do
      env = BaseUrl.call(%Tesla.Env{url: "path"}, [], "http://example.com")
      assert env.url == "http://example.com/path"
    end

    test "base without slash, path with slash" do
      env = BaseUrl.call(%Tesla.Env{url: "/path"}, [], "http://example.com")
      assert env.url == "http://example.com/path"
    end

    test "base with slash, path without slash" do
      env = BaseUrl.call(%Tesla.Env{url: "path"}, [], "http://example.com/")
      assert env.url == "http://example.com/path"
    end

    test "base with slash, path with slash" do
      env = BaseUrl.call(%Tesla.Env{url: "/path"}, [], "http://example.com/")
      assert env.url == "http://example.com/path"
    end

    test "skip double append" do
      env = BaseUrl.call(%Tesla.Env{url: "http://other.foo"}, [], "http://example.com")
      assert env.url == "http://other.foo"
    end
  end



  describe "Tesla.Middleware.Query" do
    alias Tesla.Middleware.Query
    use Tesla.Middleware.TestCase, middleware: Query

    test "joining default query params" do
      env = Query.call %Tesla.Env{}, [], page: 1
      assert env.query == [page: 1]
    end

    test "should not override existing key" do
      env = Query.call %Tesla.Env{query: [page: 1]}, [], [page: 5]
      assert env.query == [page: 1, page: 5]
    end
  end



  describe "Tesla.Middleware.Headers" do
    alias Tesla.Middleware.Headers
    use Tesla.Middleware.TestCase, middleware: Headers

    test "merge headers" do
      env = Headers.call %Tesla.Env{headers: %{"Authorization" => "secret"}}, [], %{"Content-Type" => "text/plain"}
      assert env.headers == %{"Authorization" => "secret", "Content-Type" => "text/plain"}
    end
  end



  describe "Tesla.Middleware.DecodeRels" do
    alias Tesla.Middleware.DecodeRels
    use Tesla.Middleware.TestCase, middleware: DecodeRels

    test "deocde rels" do
      headers = %{"Link" => ~s(<https://api.github.com/resource?page=2>; rel="next",
                               <https://api.github.com/resource?page=5>; rel="last")}

      env = %Tesla.Env{headers: headers}
        |> Normalize.call([], nil)
        |> DecodeRels.call([], nil)

      assert env.opts[:rels] == %{
        "next" => "https://api.github.com/resource?page=2",
        "last" => "https://api.github.com/resource?page=5"
      }
    end
  end


  test "Tesla.Middleware.BaseUrlFromConfig" do
    Application.put_env(:tesla, SomeModule, [base_url: "http://example.com"])
    env = Tesla.Middleware.BaseUrlFromConfig.call %Tesla.Env{url: "/path"}, [], otp_app: :tesla, module: SomeModule
    assert env.url == "http://example.com/path"
  end
end
