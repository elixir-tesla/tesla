defmodule Tesla.Middleware.MethodOverrideTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.MethodOverride

    adapter fn env ->
      status =
        case env do
          %{method: :get} -> 200
          %{method: :post} -> 201
          %{method: _} -> 400
        end

      {:ok, %{env | status: status}}
    end
  end

  test "when method is get" do
    assert {:ok, response} = Client.get("/")

    assert response.status == 200
    refute Tesla.get_header(response, "x-http-method-override")
  end

  test "when method is post" do
    assert {:ok, response} = Client.post("/", "")

    assert response.status == 201
    refute Tesla.get_header(response, "x-http-method-override")
  end

  test "when method isn't get or post" do
    assert {:ok, response} = Client.put("/", "")

    assert response.status == 201
    assert Tesla.get_header(response, "x-http-method-override") == "put"
  end

  defmodule CustomClient do
    use Tesla

    plug Tesla.Middleware.MethodOverride, override: ~w(put)a

    adapter fn env ->
      status =
        case env do
          %{method: :get} -> 200
          %{method: :post} -> 201
          %{method: _} -> 400
        end

      {:ok, %{env | status: status}}
    end
  end

  test "when method in override list" do
    assert {:ok, response} = CustomClient.put("/", "")

    assert response.status == 201
    assert Tesla.get_header(response, "x-http-method-override") == "put"
  end

  test "when method not in override list" do
    assert {:ok, response} = CustomClient.patch("/", "")

    assert response.status == 400
    refute Tesla.get_header(response, "x-http-method-override")
  end
end
