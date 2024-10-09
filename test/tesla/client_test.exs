defmodule Tesla.ClientTest do
  use ExUnit.Case
  doctest Tesla.Client

  describe "Tesla.Client.adapter/1" do
    test "converts atom adapter properly" do
      adapter = Tesla.Adapter.Httpc

      client = Tesla.client([], adapter)

      assert adapter == Tesla.Client.adapter(client)
    end

    test "converts tuple adapter properly" do
      adapter = {Tesla.Adapter.Hackney, [recv_timeout: 30_000]}

      client = Tesla.client([], adapter)

      assert adapter == Tesla.Client.adapter(client)
    end

    test "converts function adapter properly" do
      adapter = fn env ->
        {:ok, %{env | body: "new"}}
      end

      client = Tesla.client([], adapter)

      assert adapter == Tesla.Client.adapter(client)
    end
  end

  test "converts nil adapter properly" do
    client = Tesla.client([])

    assert Tesla.Client.adapter(client) == nil
  end

  describe "Tesla.Client.middleware/1" do
    test "converts middleware properly" do
      middlewares = [
        FirstMiddleware,
        {SecondMiddleware, options: :are, fun: 1},
        fn env, _next -> env end
      ]

      client = Tesla.client(middlewares)

      assert middlewares == Tesla.Client.middleware(client)
    end
  end

  describe "Inspect.Tesla.Client" do
    test "ensures that no secrets are leaked in logs" do
      middlewares = [
        {Tesla.Middleware.BasicAuth, username: "secret", password: "secret", other: "OK"},
        {Tesla.Middleware.BearerAuth, token: "secret", other: "OK"},
        {Tesla.Middleware.DigestAuth, %{username: "secret", password: "secret", other: "OK"}}
      ]

      inspected = middlewares |> Tesla.client() |> inspect()

      refute String.contains?(inspected, "secret")
      assert String.contains?(inspected, ~s(password: "[FILTERED]"))
      assert String.contains?(inspected, ~s(username: "[FILTERED]"))
      assert String.contains?(inspected, ~s(token: "[FILTERED]"))
    end
  end
end
