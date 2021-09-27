defmodule Tesla.OpenApi.CleanTest do
  use ExUnit.Case

  import Tesla.OpenApiTest.Helpers
  import Tesla.OpenApi.Clean

  describe "with" do
    test "clean always-matching with" do
      code =
        quote do
          with {:ok, a} <- {:ok, data["a"]},
               {:ok, b} <- {:ok, data["b"]} do
            {:ok, %{a: a, b: b}}
          end
        end

      assert_code clean(code) do
        {:ok, %{a: data["a"], b: data["b"]}}
      end
    end
  end

  test "clean unecessary with to error" do
    code =
      quote do
        with(
          {:ok, data} <-
            {:ok, %{callstack: body["callstack"], error: body["error"], ok: body["ok"]}}
        ) do
          {:error, data}
        end
      end

    assert_code clean(code) do
      {:error, %{callstack: body["callstack"], error: body["error"], ok: body["ok"]}}
    end
  end

  test "clean cond with the same results" do
    code =
      quote do
        cond do
          is_list(data.x) -> data.x
          true -> data.x
        end
      end

    assert_code clean(code) do
      data.x
    end
  end

  test "reorder cond clauses" do
    code =
      quote do
        cond do
          true -> {:ok, data}
          is_map(data) -> Model.decode(data)
        end
      end

    assert_code clean(code) do
      cond do
        is_map(data) -> Model.decode(data)
        true -> {:ok, data}
      end
    end
  end
end
