defmodule TestPetstore do
  use Tesla.OpenApi, spec: "test/support/openapi/petstore-simple.json"
end

defmodule TestPetstoreAdapter do
  @headers [{"content-type", "application/json"}]
  def call(%{method: :get, url: "/pets"}, _opts) do
    {:ok, %Tesla.Env{status: 200, body: [], headers: @headers}}
  end

  def call(%{method: :get, url: "/pets/1"}, _opts) do
    {:ok, %Tesla.Env{status: 200, body: ~s|{"id": 1}|, headers: @headers}}
  end

  def call(%{method: :get, url: "/pets/404"}, _opts) do
    {:ok,
     %Tesla.Env{
       status: 404,
       body: ~s|{"code": 1, "type": "error", "message": "Pet not found"}|,
       headers: @headers
     }}
  end
end

defmodule Tesla.OpenApiTest do
  use ExUnit.Case

  setup do
    client = TestPetstore.new(adapter: TestPetstoreAdapter)
    [client: client]
  end

  describe "find_pets" do
    test "empty", %{client: client} do
      assert {:ok, []} = TestPetstore.find_pets(client)
    end
  end

  describe "find_pet_by_id" do
    test "found", %{client: client} do
      assert {:ok, pet} = TestPetstore.find_pet_by_id(client, 1)
      assert %TestPetstore.Pet{id: 1} = pet
    end

    test "not found", %{client: client} do
      assert {:error, error} = TestPetstore.find_pet_by_id(client, 404)
      assert %TestPetstore.ErrorModel{code: 1} = error
    end
  end
end
