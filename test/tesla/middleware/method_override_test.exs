defmodule MethodOverrideTest do
  use ExUnit.Case

  use Tesla.Middleware.TestCase, middleware: Tesla.Middleware.MethodOverride


  defmodule Client do
    use Tesla

    plug Tesla.Middleware.MethodOverride

    adapter fn (env) ->
      status = case env do
        %{method: :get} -> 200
        %{method: :post} -> 201
        %{method: _} -> 400
      end

      %{env | status: status}
    end
  end

  test "when method is get" do
    response = Client.get("/")

    assert response.status == 200
    refute response.headers["x-http-method-override"]
  end

  test "when method is post" do
    response = Client.post("/", "")

    assert response.status == 201
    refute response.headers["x-http-method-override"]
  end

  test "when method isn't get or post" do
    response = Client.put("/", "")

    assert response.status == 201
    assert response.headers["x-http-method-override"] == "put"
  end

  defmodule CustomClient do
    use Tesla

    plug Tesla.Middleware.MethodOverride, override: ~w(put)a

    adapter fn (env) ->
      status = case env do
        %{method: :get} -> 200
        %{method: :post} -> 201
        %{method: _} -> 400
      end

      %{env | status: status}
    end
  end

  test "when method in override list" do
    response = CustomClient.put("/", "")

    assert response.status == 201
    assert response.headers["x-http-method-override"] == "put"
  end

  test "when method not in override list" do
    response = CustomClient.patch("/", "")

    assert response.status == 400
    refute response.headers["x-http-method-override"]
  end

end
