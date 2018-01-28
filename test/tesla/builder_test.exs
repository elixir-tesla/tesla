defmodule Tesla.BuilderTest do
  use ExUnit.Case

  alias Tesla.Builder

  describe "Compilation" do
    defmodule TestClientPlug do
      use Tesla.Builder

      @attr "value"

      plug FirstMiddleware, @attr
      plug SecondMiddleware, options: :are, fun: 1
      plug ThirdMiddleware
      plug :local_middleware
      plug fn env, _next -> env end
    end

    defmodule TestClientModule do
      use Tesla.Builder
      adapter TheAdapter, hello: "world"
    end

    defmodule TestClientFunction do
      use Tesla.Builder
      adapter :local_adapter
    end

    defmodule TestClientAnon do
      use Tesla.Builder
      adapter fn env -> env end
    end


    test "generate __middleware__/0" do
      assert [
        {FirstMiddleware, :call, ["value"]},
        {SecondMiddleware, :call, [[options: :are, fun: 1]]},
        {ThirdMiddleware, :call, [nil]},
        {TestClientPlug, :local_middleware, []},
        {:fn, fun}
      ] = TestClientPlug.__middleware__
      assert is_function(fun)
    end

    test "generate __adapter__/0 - adapter not set" do
      assert TestClientPlug.__adapter__ == nil
    end

    test "generate __adapter__/0 - adapter as module" do
      assert TestClientModule.__adapter__ == {TheAdapter, :call, [[hello: "world"]]}
    end

    test "generate __adapter__/0 - adapter as module function" do
      assert TestClientFunction.__adapter__ == {TestClientFunction, :local_adapter, []}
    end

    test "generate __adapter__/0 - adapter as anonymous function" do
      assert {:fn, fun} = TestClientAnon.__adapter__
      assert is_function(fun)
    end
  end

  describe ":only/:except options" do
    defmodule OnlyGetClient do
      use Builder, only: [:get]
    end

    defmodule ExceptDeleteClient do
      use Builder, except: ~w(delete)a
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

  describe ":docs option" do
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
end
