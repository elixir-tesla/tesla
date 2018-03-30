defmodule Tesla.MockTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla
    plug Tesla.Middleware.JSON
  end

  Application.put_env(:tesla, Tesla.MockTest.Client, adapter: Tesla.Mock)

  import Tesla.Mock

  defp setup_mock(_) do
    mock(fn
      %{url: "/ok-tuple"} ->
        {:ok, %Tesla.Env{status: 200, body: "hello tuple"}}

      %{url: "/tuple"} ->
        {201, [{"content-type", "application/json"}], ~s"{\"id\":42}"}

      %{url: "/env"} ->
        %Tesla.Env{status: 200, body: "hello env"}

      %{url: "/error"} ->
        {:error, :some_error}

      %{url: "/other"} ->
        :econnrefused

      %{url: "/json"} ->
        json(%{json: 123})

      %{method: :post, url: "/match-body", body: ~s({"some":"data"})} ->
        {201, [{"content-type", "application/json"}], ~s"{\"id\":42}"}
    end)

    :ok
  end

  describe "with mock" do
    setup :setup_mock

    test "raise on unmocked request" do
      assert_raise Tesla.Mock.Error, fn ->
        Client.get("/unmocked")
      end
    end

    test "return {:ok, env} tuple" do
      assert {:ok, %Tesla.Env{} = env} = Client.get("/ok-tuple")
      assert env.status == 200
      assert env.body == "hello tuple"
    end

    test "return {status, headers, body} tuple" do
      assert {:ok, %Tesla.Env{} = env} = Client.get("/tuple")
      assert env.status == 201
      assert env.headers == [{"content-type", "application/json"}]
      assert env.body == %{"id" => 42}
    end

    test "return env" do
      assert {:ok, %Tesla.Env{} = env} = Client.get("/env")
      assert env.status == 200
      assert env.body == "hello env"
    end

    test "return {:error, reason} tuple" do
      assert {:error, :some_error} = Client.get("/error")
    end

    test "return other error" do
      assert {:error, :econnrefused} = Client.get("/other")
    end

    test "return json" do
      assert {:ok, %Tesla.Env{} = env} = Client.get("/json")
      assert env.status == 200
      assert env.body == %{"json" => 123}
    end

    test "mock post request" do
      assert {:ok, %Tesla.Env{} = env} = Client.post("/match-body", %{"some" => "data"})
      assert env.status == 201
      assert env.body == %{"id" => 42}
    end
  end

  describe "without mock" do
    test "raise on unmocked request" do
      assert_raise Tesla.Mock.Error, fn ->
        Client.get("/return-env")
      end
    end
  end

  describe "json/2" do
    test "defaults" do
      assert %Tesla.Env{status: 200, headers: [{"content-type", "application/json"}]} =
               json("data")
    end

    test "custom status" do
      assert %Tesla.Env{status: 404} = json("data", status: 404)
    end
  end
end
