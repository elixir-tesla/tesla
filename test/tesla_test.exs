defmodule TeslaTest do
  use ExUnit.Case
  doctest Tesla

  require Tesla

  @url "http://localhost:#{Application.get_env(:httparrot, :http_port)}"

  describe "Adapters" do
    defmodule ModuleAdapter do
      def call(env, opts) do
        {:ok, Map.put(env, :url, env.url <> "/module/" <> opts[:with])}
      end
    end

    defmodule EmptyClient do
      use Tesla
    end

    defmodule ModuleAdapterClient do
      use Tesla

      adapter ModuleAdapter, with: "someopt"
    end

    defmodule FunAdapterClient do
      use Tesla

      adapter fn env ->
        {:ok, Map.put(env, :url, env.url <> "/anon")}
      end
    end

    defmodule OptsAdapter do
      def call(env, opts) do
        {:ok, %{env | body: Tesla.Adapter.opts(env, opts)}}
      end
    end

    defmodule OptsClient do
      use Tesla
      adapter OptsAdapter, static: :always
    end

    setup do
      # clean config
      Application.delete_env(:tesla, EmptyClient)
      Application.delete_env(:tesla, ModuleAdapterClient)
      :ok
    end

    test "defauilt adapter" do
      assert Tesla.effective_adapter(EmptyClient) == {Tesla.Adapter.Httpc, :call, [[]]}
    end

    test "use adapter override from config" do
      Application.put_env(:tesla, EmptyClient, adapter: Tesla.Mock)
      assert Tesla.effective_adapter(EmptyClient) == {Tesla.Mock, :call, [[]]}
    end

    test "prefer config over module setting" do
      Application.put_env(:tesla, ModuleAdapterClient, adapter: Tesla.Mock)
      assert Tesla.effective_adapter(ModuleAdapterClient) == {Tesla.Mock, :call, [[]]}
    end

    test "execute module adapter" do
      assert {:ok, response} = ModuleAdapterClient.request(url: "test")
      assert response.url == "test/module/someopt"
    end

    test "execute anonymous function adapter" do
      assert {:ok, response} = FunAdapterClient.request(url: "test")
      assert response.url == "test/anon"
    end

    test "pass only :adapter opts to adapter" do
      assert {:ok, env} = OptsClient.get("/")
      assert env.body == [static: :always]

      assert {:ok, env} = OptsClient.get("/", opts: [ignore: :me])
      assert env.body == [static: :always]

      assert {:ok, env} = OptsClient.get("/", opts: [adapter: [include: :me]])
      assert env.body == [static: :always, include: :me]

      assert {:ok, env} = OptsClient.get("/", opts: [adapter: [static: :override]])
      assert env.body == [static: :override]
    end
  end

  describe "Middleware" do
    defmodule AppendOne do
      @behaviour Tesla.Middleware

      def call(env, next, _opts) do
        env
        |> Map.put(:url, "#{env.url}/1")
        |> Tesla.run(next)
      end
    end

    defmodule AppendWith do
      @behaviour Tesla.Middleware

      def call(env, next, opts) do
        env
        |> Map.update!(:url, fn url -> url <> "/MB" <> opts[:with] end)
        |> Tesla.run(next)
        |> case do
          {:ok, env} ->
            {:ok, Map.update!(env, :url, fn url -> url <> "/MA" <> opts[:with] end)}

          error ->
            error
        end
      end
    end

    defmodule AppendClient do
      use Tesla

      plug AppendOne
      plug AppendWith, with: "1"
      plug AppendWith, with: "2"

      adapter fn env -> {:ok, env} end
    end

    test "execute middleware top down" do
      assert {:ok, response} = AppendClient.get("one")
      assert response.url == "one/1/MB1/MB2/MA2/MA1"
    end
  end

  describe "Dynamic client" do
    defmodule DynamicClient do
      use Tesla

      adapter fn env ->
        if String.ends_with?(env.url, "/cached") do
          {:ok, %{env | body: "cached", status: 304}}
        else
          Tesla.run_default_adapter(env)
        end
      end

      def help(client \\ %Tesla.Client{}) do
        get(client, "/help")
      end
    end

    test "override adapter - Tesla.client" do
      client =
        Tesla.client([], fn env ->
          {:ok, %{env | body: "new"}}
        end)

      assert {:ok, %{body: "new"}} = DynamicClient.help(client)
    end

    test "statically override adapter" do
      assert {:ok, %{status: 200}} = DynamicClient.get(@url <> "/ip")
      assert {:ok, %{status: 304}} = DynamicClient.get(@url <> "/cached")
    end
  end

  describe "request API" do
    defmodule SimpleClient do
      use Tesla

      adapter fn
        %{url: "/error"} -> {:error, :generic}
        env -> {:ok, env}
      end
    end

    test "basic request" do
      assert {:ok, response} =
               SimpleClient.request(url: "/", method: :post, query: [page: 1], body: "data")

      assert response.method == :post
      assert response.url == "/"
      assert response.query == [page: 1]
      assert response.body == "data"
    end

    test "shortcut function" do
      assert {:ok, response} = SimpleClient.get("/get")
      assert response.method == :get
      assert response.url == "/get"
    end

    test "shortcut function with body" do
      assert {:ok, response} = SimpleClient.post("/post", "some-data")
      assert response.method == :post
      assert response.url == "/post"
      assert response.body == "some-data"
    end

    test "better errors when given nil opts" do
      assert_raise FunctionClauseError, fn ->
        SimpleClient.get("/", nil)
      end
    end

    test "return error tuple for normal functions" do
      assert {:error, :generic} = SimpleClient.get("/error")
    end

    test "raise for bang variants" do
      assert_raise Tesla.Error, ~r//, fn ->
        SimpleClient.get!("/error")
      end
    end
  end

  alias Tesla.Env
  import Tesla

  describe "get_headers/2" do
    test "none matching" do
      env = %Env{headers: [{"server", "Cowboy"}]}
      assert get_headers(env, "cookie") == []
    end

    test "multiple matches matching" do
      env = %Env{headers: [{"cookie", "chocolate"}, {"cookie", "biscuits"}]}
      assert get_headers(env, "cookie") == ["chocolate", "biscuits"]
    end
  end

  describe "put_header/3" do
    test "add new header" do
      env = %Env{}
      env = put_header(env, "server", "Cowboy")
      assert get_header(env, "server") == "Cowboy"
    end

    test "override existing header" do
      env = %Env{headers: [{"server", "Cowboy"}]}
      env = put_header(env, "server", "nginx")
      assert get_header(env, "server") == "nginx"
    end
  end

  describe "put_headers/2" do
    test "add headers to env existing header" do
      env = %Env{}
      assert get_header(env, "server") == nil

      env = Tesla.put_headers(env, [{"server", "Cowboy"}, {"content-length", "100"}])
      assert get_header(env, "server") == "Cowboy"
      assert get_header(env, "content-length") == "100"

      env = Tesla.put_headers(env, [{"server", "nginx"}, {"content-type", "text/plain"}])
      assert get_header(env, "server") == "Cowboy"
      assert get_header(env, "content-length") == "100"
      assert get_header(env, "content-type") == "text/plain"
    end

    test "add multiple headers with the same name" do
      env = %Env{}
      env = Tesla.put_headers(env, [{"cookie", "chocolate"}, {"cookie", "biscuits"}])
      assert get_headers(env, "cookie") == ["chocolate", "biscuits"]
    end
  end

  describe "delete_header/2" do
    test "delete all headers with given name" do
      env = %Env{headers: [{"cookie", "chocolate"}, {"server", "Cowboy"}, {"cookie", "biscuits"}]}
      env = delete_header(env, "cookie")
      assert get_header(env, "cookie") == nil
      assert get_header(env, "server") == "Cowboy"
    end
  end

  describe "build_url/2" do
    setup do
      {:ok, url: "http://api.example.com"}
    end

    test "returns URL with query params from keyword list", %{url: url} do
      query_params = [user: 3, page: 2]
      assert build_url(url, query_params) === url <> "?user=3&page=2"
    end

    test "returns URL with query params from nested keyword list", %{url: url} do
      query_params = [nested: [more_nested: [argument: 1]]]
      assert build_url(url, query_params) === url <> "?nested%5Bmore_nested%5D%5Bargument%5D=1"
    end

    test "returns URL with query params from tuple list", %{url: url} do
      query_params = [{"user", 3}, {"page", 2}]
      assert build_url(url, query_params) === url <> "?user=3&page=2"
    end

    test "returns URL with query params from nested tuple list", %{url: url} do
      query_params = [{"nested", [{"more_nested", [{"argument", 1}]}]}]
      assert build_url(url, query_params) === url <> "?nested%5Bmore_nested%5D%5Bargument%5D=1"
    end

    test "returns URL with new query params concated from keyword list", %{url: url} do
      url_with_param = url <> "?user=4"
      query_params = [page: 2, status: true]
      assert build_url(url_with_param, query_params) === url <> "?user=4&page=2&status=true"
    end

    test "returns normal URL when query list is empty", %{url: url} do
      assert build_url(url, []) == url
    end

    test "returns error when passing wrong params" do
      wrong_url = 2
      wrong_query = :test

      assert_raise FunctionClauseError, fn ->
        build_url(wrong_url, wrong_query)
      end
    end
  end
end
