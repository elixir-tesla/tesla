defmodule Tesla.MockTest do
  use ExUnit.Case

  defp setup_mock(_) do
    Tesla.Mock.mock(fn
      %{method: :get, url: "http://example.com/list"} -> %Tesla.Env{status: 200, body: "hello"}
      %{method: :post, url: "http://example.com/create"} -> {201, %{}, %{id: 42}}
    end)

    :ok
  end

  describe "with mock" do
    setup :setup_mock

    test "mock get request" do
      assert %Tesla.Env{} = env = MockClient.list()
      assert env.status == 200
      assert env.body == "hello"
    end

    test "raise on unmocked request" do
      assert_raise Tesla.Mock.Error, fn ->
        MockClient.search()
      end
    end

    test "mock post request" do
      assert %Tesla.Env{} = env = MockClient.create(%{"some" => "data"})
      assert env.status == 201
      assert env.body.id == 42
    end
  end

  describe "without mock" do
    test "raise on unmocked request" do
      assert_raise Tesla.Mock.Error, fn ->
        MockClient.search()
      end
    end
  end
end
