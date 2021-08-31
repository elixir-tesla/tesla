defmodule Tesla.OpenApiTest do
  use ExUnit.Case

  defmodule PetstoreMinimal do
    use Tesla.OpenApi, spec: "test/support/openapi/petstore-minimal.json"
  end

  defmodule PetstoreSimple do
    use Tesla.OpenApi, spec: "test/support/openapi/petstore-simple.json"
  end

  defmodule Petstore do
    use Tesla.OpenApi, spec: "test/support/openapi/petstore.json"
  end

  defmodule PetstoreExpanded do
    use Tesla.OpenApi, spec: "test/support/openapi/petstore-expanded.json"
  end

  # defmodule Slack do
  #   use Tesla.OpenApi, spec: "test/support/openapi/slack_web_openapi_v2.json"
  # end

  defmodule PetstoreAdapter do
    @headers [{"content-type", "application/json"}]
    def call(%{method: :get, url: "http://petstore.swagger.io/api/pets"}, _opts) do
      {:ok, %Tesla.Env{status: 200, body: [], headers: @headers}}
    end

    def call(%{method: :get, url: "http://petstore.swagger.io/api/pets/1"}, _opts) do
      {:ok, %Tesla.Env{status: 200, body: ~s|{"id": 1}|, headers: @headers}}
    end

    def call(%{method: :get, url: "http://petstore.swagger.io/api/pets/404"}, _opts) do
      {:ok,
       %Tesla.Env{
         status: 404,
         body: ~s|{"code": 1, "type": "error", "message": "Pet not found"}|,
         headers: @headers
       }}
    end
  end

  # setup do
  #   client = PetstoreSimple.new(adapter: PetstoreAdapter)
  #   [client: client]
  # end

  # describe "find_pets" do
  #   test "empty", %{client: client} do
  #     assert {:ok, []} = PetstoreSimple.find_pets(client)
  #   end
  # end

  # describe "find_pet_by_id" do
  #   test "found", %{client: client} do
  #     assert {:ok, pet} = PetstoreSimple.find_pet_by_id(client, 1)
  #     assert %PetstoreSimple.Pet{id: 1} = pet
  #   end

  #   test "not found", %{client: client} do
  #     assert {:error, error} = PetstoreSimple.find_pet_by_id(client, 404)
  #     assert %PetstoreSimple.ErrorModel{code: 1} = error
  #   end
  # end

  # test "uber" do
  #   defmodule Uber do
  #     use Tesla.OpenApi, spec: "test/support/openapi/uber.json"
  #   end
  # end

  test "slack" do
    # defmodule Slack do
    #   use Tesla.OpenApi, spec: "test/support/openapi/slack_web_openapi_v2.json"
    # end
  end
end
