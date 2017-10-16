defmodule Tesla.MockTest do
  use ExUnit.Case

  defp setup_config(_) do
    Application.put_env(:tesla, :adapter, :mock)
    :ok
  end

  defp setup_mock(_) do
    Tesla.Mock.mock fn
      %{method: :get,  url: "http://example.com/list_of_maps"}   -> %Tesla.Env{status: 200, body: [%{hello: "world"}]}
      %{method: :get,  url: "http://example.com/list"}   -> %Tesla.Env{status: 200, body: "hello"}
      %{method: :post, url: "http://example.com/create"} -> {201, %{}, %{id: 42}}
    end

    :ok
  end

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.BaseUrl, "http://example.com"
    plug Tesla.Middleware.JSON

    def list do
      get("/list")
    end

    def list_of_maps do
      get("/list_of_maps")
    end
    def search() do
      get("/search")
    end

    def create(data) do
      post("/create", data)
    end
  end

  describe "with mock" do
    setup [:setup_config, :setup_mock]

    test "mock get request list of maps" do
      assert %Tesla.Env{} = env = Client.list_of_maps()
      assert env.status == 200
      assert env.body == [%{hello: "world"}]
    end

    test "mock get request" do
      assert %Tesla.Env{} = env = Client.list()
      assert env.status == 200
      assert env.body == "hello"
    end

    test "mock get request (list of maps)" do
      assert %Tesla.Env{} = env = Client.list_of_maps()
      assert env.status == 200
      assert env.body == [%{hello: "world"}]
    end



    test "raise on unmocked request" do
      assert_raise Tesla.Mock.Error, fn ->
        Client.search()
      end
    end

    test "mock post request" do
      assert %Tesla.Env{} = env = Client.create(%{"some" => "data"})
      assert env.status == 201
      assert env.body.id == 42
    end
  end

  describe "without mock" do
    setup [:setup_config]

    test "raise on unmocked request" do
      assert_raise Tesla.Mock.Error, fn ->
        Client.search()
      end
    end
  end
end
