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

    test "compile error when using atom as adapter" do
      assert_raise CompileError, fn ->
        Code.compile_quoted(quote do
          defmodule Client2 do
            use Tesla
            adapter :hackney
          end
        end)
      end
    end

    test "compile error when using atom as adapter in config" do
      assert_raise CompileError, fn ->
        Application.put_env(:tesla, Client3, adapter: :mock)
        Code.compile_quoted(quote do
          defmodule Client3 do
            use Tesla
          end
        end)
      end
    end
  end
end
