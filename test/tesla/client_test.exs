defmodule Tesla.ClientTest do
  use ExUnit.Case
  doctest Tesla.Client

  alias Tesla.Client

  describe "Tesla.Client.adapter/1" do
    test "converts atom adapter properly" do
      adapter = Tesla.Adapter.Httpc

      client = Tesla.client([], adapter)

      assert adapter == Client.adapter(client)
    end

    test "converts tuple adapter properly" do
      adapter = {Tesla.Adapter.Hackney, [recv_timeout: 30_000]}

      client = Tesla.client([], adapter)

      assert adapter == Client.adapter(client)
    end

    test "converts function adapter properly" do
      adapter = fn env ->
        {:ok, %{env | body: "new"}}
      end

      client = Tesla.client([], adapter)

      assert adapter == Client.adapter(client)
    end
  end

  test "converts nil adapter properly" do
    client = Tesla.client([])

    assert Client.adapter(client) == nil
  end

  describe "update_middleware/2" do
    test "prepends middleware" do
      client = Tesla.client([FirstMiddleware])

      new_client = Client.update_middleware(client, &([SecondMiddleware] ++ &1))

      assert Client.middleware(new_client) == [SecondMiddleware, FirstMiddleware]
    end

    test "appends middleware" do
      client = Tesla.client([FirstMiddleware])

      new_client = Client.update_middleware(client, &(&1 ++ [SecondMiddleware]))

      assert Client.middleware(new_client) == [FirstMiddleware, SecondMiddleware]
    end

    test "filters middleware" do
      client = Tesla.client([FirstMiddleware, SecondMiddleware])

      new_client =
        Client.update_middleware(client, &Enum.reject(&1, fn m -> m == FirstMiddleware end))

      assert Client.middleware(new_client) == [SecondMiddleware]
    end

    test "preserves atom adapter" do
      adapter = Tesla.Adapter.Httpc
      client = Tesla.client([FirstMiddleware], adapter)

      new_client = Client.update_middleware(client, &(&1 ++ [SecondMiddleware]))

      assert Client.adapter(new_client) == adapter
    end

    test "preserves tuple adapter" do
      adapter = {Tesla.Adapter.Hackney, [recv_timeout: 30_000]}
      client = Tesla.client([FirstMiddleware], adapter)

      new_client = Client.update_middleware(client, &(&1 ++ [SecondMiddleware]))

      assert Client.adapter(new_client) == adapter
    end

    test "preserves function adapter" do
      adapter = fn env -> {:ok, env} end
      client = Tesla.client([FirstMiddleware], adapter)

      new_client = Client.update_middleware(client, &(&1 ++ [SecondMiddleware]))

      assert Client.adapter(new_client) == adapter
    end

    test "preserves nil adapter" do
      client = Tesla.client([FirstMiddleware])

      new_client = Client.update_middleware(client, &(&1 ++ [SecondMiddleware]))

      assert Client.adapter(new_client) == nil
    end
  end

  describe "Tesla.Client.middleware/1" do
    test "converts middleware properly" do
      middlewares = [
        FirstMiddleware,
        {SecondMiddleware, options: :are, fun: 1},
        fn env, _next -> env end
      ]

      client = Tesla.client(middlewares)

      assert middlewares == Client.middleware(client)
    end
  end
end
