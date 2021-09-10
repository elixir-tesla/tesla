defmodule Tesla.OpenApiTest do
  use ExUnit.Case

  # These tests are based on specs stored in test/support/openapi directory

  describe "Petstore" do
    defmodule Petstore do
      use Tesla.OpenApi, spec: "test/support/openapi/petstore.json"

      def new_with_telemetry() do
        # In case certain middleware needs to be inserted in the middle of the existing stack
        # use Tesla.Client.insert/3
        new([], PetstoreAdapter)
        |> Tesla.Client.insert(Tesla.Middleware.Telemetry, before: Tesla.Middleware.PathParams)
      end
    end

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

    setup do
      [client: Petstore.new([], PetstoreAdapter)]
    end

    test "find_pets", %{client: client} do
      assert {:ok, []} = Petstore.find_pets(client)
    end

    test "find_pet_by_id - found", %{client: client} do
      assert {:ok, pet} = Petstore.find_pet_by_id(client, 1)
      assert %Petstore.Pet{id: 1} = pet
    end

    test "find_pet_by_id - not found", %{client: client} do
      assert {:error, error} = Petstore.find_pet_by_id(client, 404)
      assert %Petstore.ErrorModel{code: 1} = error
    end

    test "new_with_telemetry" do
      assert %Tesla.Client{
               pre: [
                 _,
                 {Tesla.Middleware.Telemetry, _, _},
                 {Tesla.Middleware.PathParams, _, _},
                 _,
                 _,
                 _
               ]
             } = Petstore.new_with_telemetry()
    end
  end

  describe "Slack" do
    defmodule Slack do
      use Tesla.OpenApi, spec: "test/support/openapi/slack.json"
    end

    test "new/0" do
      assert %Tesla.Client{} = Slack.new()
    end
  end

  describe "Realworld" do
    defmodule Realworld do
      use Tesla.OpenApi, spec: "test/support/openapi/realworld.json"
    end

    setup do
      [client: Realworld.new([], Tesla.Mock)]
    end

    test "get_current_user", %{client: client} do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/json"}],
            body: """
            {
              "user": {
                "email": "jon@example.com",
                "token": "xyz",
                "username": "jon",
                "bio": "",
                "image": ""
              }
            }
            """
          }
      end)

      assert {:ok, %Realworld.UserResponse{user: user}} = Realworld.get_current_user(client)
      assert %Realworld.User{email: "jon@example.com"} = user
    end

    test "get_current_user - Unauthorized", %{client: client} do
      Tesla.Mock.mock(fn
        %{method: :get} -> %Tesla.Env{status: 401}
      end)

      assert {:error, 401} = Realworld.get_current_user(client)
    end

    test "get_current_user - Error", %{client: client} do
      Tesla.Mock.mock(fn
        %{method: :get} ->
          %Tesla.Env{
            status: 422,
            headers: [{"content-type", "application/json"}],
            body: """
            {
              "errors": {
                "body": ["invalid"]
              }
            }
            """
          }
      end)

      assert {:error, %{errors: %{body: ["invalid"]}}} = Realworld.get_current_user(client)
    end

    test "login", %{client: client} do
      Tesla.Mock.mock(fn
        %{method: :post, url: "/api/users/login", body: body} ->
          assert %{"user" => %{"email" => "jon@example.com", "password" => "password"}} ==
                   Jason.decode!(body)

          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/json"}],
            body: """
            {
              "user": {
                "email": "jon@example.com",
                "token": "xyz",
                "username": "jon",
                "bio": "",
                "image": ""
              }
            }
            """
          }
      end)

      body = %Realworld.LoginUserRequest{
        user: %Realworld.LoginUser{email: "jon@example.com", password: "password"}
      }

      assert {:ok, %{user: %{token: "xyz"}}} = Realworld.login(client, body)
    end
  end
end
