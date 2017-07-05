defmodule TeslaTest do
  use ExUnit.Case
  doctest TeslaDocsTest.Doctest

  describe "Macros" do
    defmodule Mc do
      defmodule Basic.Middleware.Plus do
        def call(env, next, opts) do
          env
          |> Map.put(:url, "#{env.url}/#{opts[:with]}")
          |> Tesla.run(next)
        end
      end

      defmodule Basic.Middleware.Plus1 do
        def call(env, next, _opts) do
          env
          |> Map.put(:url, "#{env.url}/1")
          |> Tesla.run(next)
        end
      end

      defmodule Basic do
        use Tesla

        plug Basic.Middleware.Plus, with: "engine"
        plug Basic.Middleware.Plus1
        plug :some_function

        adapter :some_adapter, some: "opts"
      end

      defmodule Empty do
        use Tesla
      end

      defmodule Fun do
        use Tesla

        adapter fn env ->
          Map.put(env, :url, "#{env.url}/anon")
        end
      end

      defmodule Only do
        use Tesla, only: [:get]
      end

      defmodule Except do
        use Tesla.Builder, except: ~w(delete)a
      end
    end

    @http_verbs ~w(head get delete trace options post put patch)a

    test "middleware list" do
      assert Mc.Basic.__middleware__ == [
        {Mc.Basic.Middleware.Plus,   [with: "engine"]},
        {Mc.Basic.Middleware.Plus1,  nil},
        {:some_function,          nil}
      ]

      assert Mc.Basic.__adapter__ == {:some_adapter, some: "opts"}
    end

    test "defauilt adapter" do
      assert Mc.Empty.__adapter__ == Tesla.default_adapter
    end

    test "adapter as function" do
      assert is_function(Mc.Fun.__adapter__)
    end

    test "limit generated functions (only)" do
      functions = Mc.Only.__info__(:functions) |> Keyword.keys() |> Enum.uniq
      assert :get in functions
      refute Enum.any?(@http_verbs -- [:get], &(&1 in functions))
    end

    test "limit generated functions (except)" do
      functions = Mc.Except.__info__(:functions) |> Keyword.keys() |> Enum.uniq
      refute :delete in functions
      assert Enum.all?(@http_verbs -- [:delete], &(&1 in functions))
    end
  end

  describe "docs" do
    # Code.get_docs/2 requires .beam file of given module to exist in file system
    # See test/support/docs.ex file for definitions of TeslaDocsTest.* modules

    test "generate docs by default" do
      docs = Code.get_docs(TeslaDocsTest.Default, :docs)
      assert {_, _, _, _, doc} = Enum.find(docs, &match?({{:get, 1}, _, :def, _, _}, &1))
      assert doc != false
    end

    test "do not generate docs for HTTP methods when docs: false" do
      docs = Code.get_docs(TeslaDocsTest.NoDocs, :docs)
      assert {_, _, _, _, false}  = Enum.find(docs, &match?({{:get, 1}, _, :def, _, _}, &1))
      assert {_, _, _, _, doc}    = Enum.find(docs, &match?({{:custom, 1}, _, :def, _, _}, &1))
      assert doc =~ ~r/something/
    end
  end


  describe "Middleware" do
    defmodule M do
      defmodule Mid do
        def call(env, next, opts) do
          env
          |> Map.update!(:url, fn url -> url <> "/module/" <> opts[:before] end)
          |> Tesla.run(next)
          |> Map.update!(:url, fn url -> url <> "/module/" <> opts[:after] end)
        end
      end

      defmodule Client do
        use Tesla

        plug Mid, before: "A", after: "B"
        plug :local_middleware

        adapter fn env -> env end

        def local_middleware(env, next) do
          env
          |> Map.put(:url, env.url <> "/local")
          |> Tesla.run(next)
        end
      end
    end

    test "execute middleware top down" do
      response = M.Client.request(url: "one")
      assert response.url == "one/module/A/local/module/B"
    end
  end



  describe "Adapters" do
    defmodule A do
      defmodule Adapter do
        def call(env, opts \\ []) do
          Map.put(env, :url, env.url <> "/module/" <> opts[:with])
        end
      end

      defmodule ClientModule do
        use Tesla
        adapter Adapter, with: "someopt"
      end

      defmodule ClientLocal do
        use Tesla
        adapter :local_adapter
        def local_adapter(env) do
          Map.put(env, :url, env.url <> "/local")
        end
      end

      defmodule ClientAnon do
        use Tesla
        adapter fn env ->
          Map.put(env, :url, env.url <> "/anon")
        end
      end
    end

    test "execute module adapter" do
      response = A.ClientModule.request(url: "test")
      assert response.url == "test/module/someopt"
    end

    test "execute local function adapter" do
      response = A.ClientLocal.request(url: "test")
      assert response.url == "test/local"
    end

    test "execute anonymous function adapter" do
      response = A.ClientAnon.request(url: "test")
      assert response.url == "test/anon"
    end
  end



  describe "request API" do
    defmodule R do
      defmodule Client do
        use Tesla

        adapter fn env ->
          env
        end

        def new do
          Tesla.build_client [
            {R.Mid1, [with: "/mid1"]},
            {R.Mid2, nil},
            :local_middleware
          ]
        end

        def local_middleware(env, next) do
          env
          |> Map.put(:url, env.url <> "/local")
          |> Tesla.run(next)
        end
      end

      defmodule Mid1 do
        def call(env, next, opts) do
          env
          |> Map.put(:url, env.url <> opts[:with])
          |> Tesla.run(next)
        end
      end

      defmodule Mid2 do
        def call(env, next, _opts) do
          env
          |> Map.put(:url, env.url <> "/mid2")
          |> Tesla.run(next)
        end
      end
    end

    test "basic request" do
      response = R.Client.request(url: "/", method: :post, query: [page: 1], body: "data")
      assert response.method  == :post
      assert response.url     == "/"
      assert response.query   == [page: 1]
      assert response.body    == "data"
    end

    test "shortcut function" do
      response = R.Client.get("/get")
      assert response.method  == :get
      assert response.url     == "/get"
    end

    test "request with client" do
      client = fn env, next ->
        env
        |> Map.put(:url, "/prefix" <> env.url)
        |> Tesla.run(next)
      end

      response = R.Client.get("/")
      assert response.url == "/"
      refute response.__client__

      response = client |> R.Client.get("/")
      assert response.url == "/prefix/"
      assert response.__client__ == client
    end

    test "build_client helper" do
      client = R.Client.new
      response = client |> R.Client.get("test")
      assert response.url == "test/mid1/mid2/local"
    end

    test "insert request middleware function at runtime" do
      fun = fn env, next ->
        env
        |> Map.put(:url, env.url <> ".json")
        |> Tesla.run(next)
      end

      res = fun |> R.Client.get("/foo")
      assert res.url == "/foo.json"
    end

    test "insert response middleware function at runtime" do
      fun = fn env, next ->
        env
        |> Tesla.run(next)
        |> Map.put(:url, env.url <> ".json")
      end

      res = fun |> R.Client.get("/foo")
      assert res.url == "/foo.json"
    end
  end
end
