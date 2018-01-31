defmodule MigrationTest do
  use ExUnit.Case

  describe "Drop aliases #159" do
    test "compile error when using atom as plug" do
      assert_raise CompileError, fn ->
        Code.compile_quoted(quote do
          defmodule Client1 do
            use Tesla
            plug :json
          end
        end)
      end
    end

    test "no error when using atom as plug and there is a local function with that name" do
      Code.compile_quoted(quote do
        defmodule Client2 do
          use Tesla
          plug :json
          def json(env, next), do: Tesla.run(env, next)
        end
      end)
    end

    test "compile error when using atom as adapter" do
      assert_raise CompileError, fn ->
        Code.compile_quoted(quote do
          defmodule Client3 do
            use Tesla
            adapter :hackney
          end
        end)
      end
    end

    test "no error when using atom as adapter and there is a local function with that name" do
      Code.compile_quoted(quote do
        defmodule Client4 do
          use Tesla
          adapter :local
          def local(env), do: env
        end
      end)
    end

    test "compile error when using atom as adapter in config" do
      assert_raise CompileError, fn ->
        Application.put_env(:tesla, Client5, adapter: :mock)
        Code.compile_quoted(quote do
          defmodule Client5 do
            use Tesla
          end
        end)
      end
    end
  end

  describe "Use keyword list to store headers #160" do
    test "compile error when passing a map to Headers middleware" do
      assert_raise CompileError, fn ->
        Code.compile_quoted(quote do
          defmodule Client6 do
            use Tesla
            plug Tesla.Middleware.Headers, %{"User-Agent" => "tesla"}
          end
        end)
      end
    end

    test "no error when passing a list to Headers middleware" do
      Code.compile_quoted(quote do
        defmodule Client7 do
          use Tesla
          plug Tesla.Middleware.Headers, [{"user-agent", "tesla"}]
        end
      end)
    end
  end
end
