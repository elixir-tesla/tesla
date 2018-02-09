defmodule TeslaTest do
  use ExUnit.Case

  require Tesla

  @url "http://localhost:#{Application.get_env(:httparrot, :http_port)}"

  describe "Adapters" do
    defmodule ModuleAdapter do
      def call(env, opts \\ []) do
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

    defmodule LocalAdapterClient do
      use Tesla

      adapter :local_adapter

      def local_adapter(env) do
        {:ok, Map.put(env, :url, env.url <> "/local")}
      end
    end

    defmodule FunAdapterClient do
      use Tesla

      adapter fn env ->
        {:ok, Map.put(env, :url, env.url <> "/anon")}
      end
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

    test "execute local function adapter" do
      assert {:ok, response} = LocalAdapterClient.request(url: "test")
      assert response.url == "test/local"
    end

    test "execute anonymous function adapter" do
      assert {:ok, response} = FunAdapterClient.request(url: "test")
      assert response.url == "test/anon"
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
      plug :local_middleware

      adapter fn env -> {:ok, env} end

      def local_middleware(env, next) do
        env
        |> Map.update!(:url, fn url -> url <> "/LB" end)
        |> Tesla.run(next)
        |> case do
          {:ok, env} ->
            {:ok, Map.update!(env, :url, fn url -> url <> "/LA" end)}

          error ->
            error
        end
      end
    end

    test "execute middleware top down" do
      assert {:ok, response} = AppendClient.get("one")
      assert response.url == "one/1/MB1/MB2/LB/LA/MA2/MA1"
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

    test "override adapter - Tesla.build_client" do
      client =
        Tesla.build_client([], [
          fn env, _next ->
            {:ok, %{env | body: "new"}}
          end
        ])

      assert {:ok, %{body: "new"}} = DynamicClient.help(client)
    end

    test "override adapter - Tesla.build_adapter" do
      client =
        Tesla.build_adapter(fn env ->
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

      adapter fn env ->
        {:ok, env}
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

    test "request with client" do
      client = fn env, next ->
        env
        |> Map.put(:url, "/prefix" <> env.url)
        |> Tesla.run(next)
      end

      assert {:ok, response} = SimpleClient.get("/")
      assert response.url == "/"
      assert response.__client__ == %Tesla.Client{}

      assert {:ok, response} = client |> SimpleClient.get("/")
      assert response.url == "/prefix/"
      assert response.__client__ == %Tesla.Client{fun: client}
    end

    test "better errors when given nil opts" do
      assert_raise FunctionClauseError, fn ->
        Tesla.get("/", nil)
      end
    end
  end

  alias Tesla.Env
  import Tesla

  describe "get_header/2" do
    test "non existing header" do
      env = %Env{headers: [{"server", "Cowboy"}]}
      assert get_header(env, "some-key") == nil
    end

    test "existing header" do
      env = %Env{headers: [{"server", "Cowboy"}]}
      assert get_header(env, "server") == "Cowboy"
    end

    test "first of multiple headers with the same name" do
      env = %Env{headers: [{"cookie", "chocolate"}, {"cookie", "biscuits"}]}
      assert get_header(env, "cookie") == "chocolate"
    end
  end

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
end
