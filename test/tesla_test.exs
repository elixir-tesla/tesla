defmodule TeslaTest do
  use ExUnit.Case

  require Tesla

  @url "http://localhost:#{Application.get_env(:httparrot, :http_port)}"

  describe "use Tesla options" do
    defmodule OnlyGetClient do
      use Tesla, only: [:get]
    end

    defmodule ExceptDeleteClient do
      use Tesla.Builder, except: ~w(delete)a
    end

    @http_verbs ~w(head get delete trace options post put patch)a

    test "limit generated functions (only)" do
      functions = OnlyGetClient.__info__(:functions) |> Keyword.keys() |> Enum.uniq()
      assert :get in functions
      refute Enum.any?(@http_verbs -- [:get], &(&1 in functions))
    end

    test "limit generated functions (except)" do
      functions = ExceptDeleteClient.__info__(:functions) |> Keyword.keys() |> Enum.uniq()
      refute :delete in functions
      assert Enum.all?(@http_verbs -- [:delete], &(&1 in functions))
    end
  end

  describe "Docs" do
    # Code.get_docs/2 requires .beam file of given module to exist in file system
    # See test/support/docs.ex file for definitions of TeslaDocsTest.* modules

    test "generate docs by default" do
      docs = Code.get_docs(TeslaDocsTest.Default, :docs)
      assert {_, _, _, _, doc} = Enum.find(docs, &match?({{:get, 1}, _, :def, _, _}, &1))
      assert doc != false
    end

    test "do not generate docs for HTTP methods when docs: false" do
      docs = Code.get_docs(TeslaDocsTest.NoDocs, :docs)
      assert {_, _, _, _, false} = Enum.find(docs, &match?({{:get, 1}, _, :def, _, _}, &1))
      assert {_, _, _, _, doc} = Enum.find(docs, &match?({{:custom, 1}, _, :def, _, _}, &1))
      assert doc =~ ~r/something/
    end
  end

  describe "Adapters" do
    defmodule ModuleAdapter do
      def call(env, opts \\ []) do
        Map.put(env, :url, env.url <> "/module/" <> opts[:with])
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
        Map.put(env, :url, env.url <> "/local")
      end
    end

    defmodule FunAdapterClient do
      use Tesla

      adapter fn env ->
        Map.put(env, :url, env.url <> "/anon")
      end
    end

    setup do
      # clean config
      Application.delete_env(:tesla, EmptyClient)
      Application.delete_env(:tesla, ModuleAdapterClient)
      :ok
    end

    test "defauilt adapter" do
      assert EmptyClient.__adapter__() == Tesla.default_adapter()
    end

    test "adapter as module" do
      assert ModuleAdapterClient.__adapter__() == {ModuleAdapter, [with: "someopt"]}
    end

    test "adapter as local function" do
      assert LocalAdapterClient.__adapter__() == {:local_adapter, nil}
    end

    test "adapter as anonymous function" do
      assert is_function(FunAdapterClient.__adapter__())
    end

    test "execute module adapter" do
      response = ModuleAdapterClient.request(url: "test")
      assert response.url == "test/module/someopt"
    end

    test "execute local function adapter" do
      response = LocalAdapterClient.request(url: "test")
      assert response.url == "test/local"
    end

    test "execute anonymous function adapter" do
      response = FunAdapterClient.request(url: "test")
      assert response.url == "test/anon"
    end

    test "use adapter override from config" do
      Application.put_env(:tesla, EmptyClient, adapter: Tesla.Mock)
      assert EmptyClient.__adapter__() == Tesla.Mock
    end

    test "prefer config over module setting" do
      Application.put_env(:tesla, ModuleAdapterClient, adapter: Tesla.Mock)
      assert ModuleAdapterClient.__adapter__() == Tesla.Mock
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
        |> Map.update!(:url, fn url -> url <> "/MA" <> opts[:with] end)
      end
    end

    defmodule AppendClient do
      use Tesla

      plug AppendOne
      plug AppendWith, with: "1"
      plug AppendWith, with: "2"
      plug :local_middleware

      adapter fn env -> env end

      def local_middleware(env, next) do
        env
        |> Map.update!(:url, fn url -> url <> "/LB" end)
        |> Tesla.run(next)
        |> Map.update!(:url, fn url -> url <> "/LA" end)
      end
    end

    test "middleware list" do
      assert AppendClient.__middleware__() == [
               {AppendOne, nil},
               {AppendWith, [with: "1"]},
               {AppendWith, [with: "2"]},
               {:local_middleware, nil}
             ]
    end

    test "execute middleware top down" do
      response = AppendClient.get("one")
      assert response.url == "one/1/MB1/MB2/LB/LA/MA2/MA1"
    end
  end

  describe "Dynamic client" do
    defmodule DynamicClient do
      use Tesla

      adapter fn env ->
        if String.ends_with?(env.url, "/cached") do
          %{env | body: "cached", status: 304}
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
            %{env | body: "new"}
          end
        ])

      assert %{body: "new"} = DynamicClient.help(client)
    end

    test "override adapter - Tesla.build_adapter" do
      client =
        Tesla.build_adapter(fn env ->
          %{env | body: "new"}
        end)

      assert %{body: "new"} = DynamicClient.help(client)
    end

    test "statically override adapter" do
      assert %{status: 200} = DynamicClient.get(@url <> "/ip")
      assert %{status: 304} = DynamicClient.get(@url <> "/cached")
    end
  end

  describe "request API" do
    defmodule SimpleClient do
      use Tesla

      adapter fn env ->
        env
      end
    end

    test "basic request" do
      response = SimpleClient.request(url: "/", method: :post, query: [page: 1], body: "data")
      assert response.method == :post
      assert response.url == "/"
      assert response.query == [page: 1]
      assert response.body == "data"
    end

    test "shortcut function" do
      response = SimpleClient.get("/get")
      assert response.method == :get
      assert response.url == "/get"
    end

    test "shortcut function with body" do
      response = SimpleClient.post("/post", "some-data")
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

      response = SimpleClient.get("/")
      assert response.url == "/"
      refute response.__client__

      response = client |> SimpleClient.get("/")
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
      assert get_header(%Env{}, "some-key") == nil
    end

    test "fetch existing header" do
      assert get_header(%Env{headers: [{"server", "Cowboy"}]}, "server") == "Cowboy"
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
      assert get_header(env, "server") == "nginx"
      assert get_header(env, "content-length") == "100"
      assert get_header(env, "content-type") == "text/plain"
    end
  end
end
