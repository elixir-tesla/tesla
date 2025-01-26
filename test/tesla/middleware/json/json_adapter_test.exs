defmodule Tesla.Middleware.JSON.JSONAdapterTest do
  use ExUnit.Case, async: true

  alias Tesla.Middleware.JSON.JSONAdapter

  describe "encode/2" do
    test "encodes as expected with default encoder" do
      assert {:ok, ~S({"hello":"world"})} == JSONAdapter.encode(%{hello: "world"}, [])
    end
  end

  describe "decode/2" do
    test "returns {:ok, term} on success" do
      assert {:ok, %{"hello" => "world"}} = JSONAdapter.decode(~S({"hello":"world"}), [])
    end

    test "returns {:error, reason} on failure" do
      assert {:error, {:invalid_byte, _, _}} = JSONAdapter.decode("invalid_json", [])
    end
  end
end
