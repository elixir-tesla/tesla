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

  describe "put_middleware/2" do
    test "replaces middleware list" do
      client = Tesla.client([FirstMiddleware])

      new_client = Client.put_middleware(client, [SecondMiddleware])

      assert Client.middleware(new_client) == [SecondMiddleware]
    end

    test "replaces with empty list" do
      client = Tesla.client([FirstMiddleware])

      new_client = Client.put_middleware(client, [])

      assert Client.middleware(new_client) == []
    end

    test "preserves atom adapter" do
      adapter = Tesla.Adapter.Httpc
      client = Tesla.client([FirstMiddleware], adapter)

      new_client = Client.put_middleware(client, [SecondMiddleware])

      assert Client.adapter(new_client) == adapter
    end

    test "preserves tuple adapter" do
      adapter = {Tesla.Adapter.Hackney, [recv_timeout: 30_000]}
      client = Tesla.client([FirstMiddleware], adapter)

      new_client = Client.put_middleware(client, [SecondMiddleware])

      assert Client.adapter(new_client) == adapter
    end

    test "preserves function adapter" do
      adapter = fn env -> {:ok, env} end
      client = Tesla.client([FirstMiddleware], adapter)

      new_client = Client.put_middleware(client, [SecondMiddleware])

      assert Client.adapter(new_client) == adapter
    end

    test "preserves nil adapter" do
      client = Tesla.client([FirstMiddleware])

      new_client = Client.put_middleware(client, [SecondMiddleware])

      assert Client.adapter(new_client) == nil
    end

    test "preserves post middleware stack" do
      client = %Client{pre: [], post: [{SecondMiddleware, :call, [[]]}]}

      new_client = Client.put_middleware(client, [ThirdMiddleware])

      assert Client.middleware(new_client) == [ThirdMiddleware]
      assert new_client.post == client.post
    end
  end

  describe "replace_middleware!/3" do
    test "replaces target atom middleware" do
      client = Tesla.client([FirstMiddleware, SecondMiddleware])

      new_client = Client.replace_middleware!(client, FirstMiddleware, ThirdMiddleware)

      assert Client.middleware(new_client) == [ThirdMiddleware, SecondMiddleware]
    end

    test "replaces target tuple middleware" do
      client = Tesla.client([{FirstMiddleware, [opt: true]}, SecondMiddleware])

      new_client = Client.replace_middleware!(client, FirstMiddleware, ThirdMiddleware)

      assert Client.middleware(new_client) == [ThirdMiddleware, SecondMiddleware]
    end

    test "raises when target not found" do
      client = Tesla.client([FirstMiddleware])

      assert_raise ArgumentError, ~r/not found/, fn ->
        Client.replace_middleware!(client, SecondMiddleware, ThirdMiddleware)
      end
    end

    test "preserves adapter" do
      adapter = Tesla.Adapter.Httpc
      client = Tesla.client([FirstMiddleware], adapter)

      new_client = Client.replace_middleware!(client, FirstMiddleware, SecondMiddleware)

      assert Client.adapter(new_client) == adapter
    end
  end

  describe "insert_middleware!/4" do
    test "inserts before target atom middleware" do
      client = Tesla.client([FirstMiddleware, SecondMiddleware])

      new_client = Client.insert_middleware!(client, ThirdMiddleware, :before, SecondMiddleware)

      assert Client.middleware(new_client) == [FirstMiddleware, ThirdMiddleware, SecondMiddleware]
    end

    test "inserts after target atom middleware" do
      client = Tesla.client([FirstMiddleware, SecondMiddleware])

      new_client = Client.insert_middleware!(client, ThirdMiddleware, :after, FirstMiddleware)

      assert Client.middleware(new_client) == [FirstMiddleware, ThirdMiddleware, SecondMiddleware]
    end

    test "inserts before target tuple middleware" do
      client = Tesla.client([{FirstMiddleware, [opt: true]}, SecondMiddleware])

      new_client = Client.insert_middleware!(client, ThirdMiddleware, :before, FirstMiddleware)

      assert Client.middleware(new_client) == [
               ThirdMiddleware,
               {FirstMiddleware, [opt: true]},
               SecondMiddleware
             ]
    end

    test "inserts after target tuple middleware" do
      client = Tesla.client([FirstMiddleware, {SecondMiddleware, [opt: true]}])

      new_client = Client.insert_middleware!(client, ThirdMiddleware, :after, SecondMiddleware)

      assert Client.middleware(new_client) == [
               FirstMiddleware,
               {SecondMiddleware, [opt: true]},
               ThirdMiddleware
             ]
    end

    test "raises when target not found" do
      client = Tesla.client([FirstMiddleware])

      assert_raise ArgumentError, ~r/not found/, fn ->
        Client.insert_middleware!(client, ThirdMiddleware, :before, SecondMiddleware)
      end
    end

    test "preserves adapter" do
      adapter = Tesla.Adapter.Httpc
      client = Tesla.client([FirstMiddleware], adapter)

      new_client = Client.insert_middleware!(client, SecondMiddleware, :before, FirstMiddleware)

      assert Client.adapter(new_client) == adapter
    end
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

  describe "update_middleware!/3" do
    test "updates atom middleware" do
      client = Tesla.client([FirstMiddleware])

      new_client =
        Client.update_middleware!(client, FirstMiddleware, fn _ -> SecondMiddleware end)

      assert Client.middleware(new_client) == [SecondMiddleware]
    end

    test "updates tuple middleware opts" do
      client = Tesla.client([{FirstMiddleware, [opt: 1]}])

      new_client =
        Client.update_middleware!(client, FirstMiddleware, fn {m, opts} ->
          {m, Keyword.put(opts, :opt, 2)}
        end)

      assert Client.middleware(new_client) == [{FirstMiddleware, [opt: 2]}]
    end

    test "updates only first occurrence" do
      client = Tesla.client([FirstMiddleware, SecondMiddleware, FirstMiddleware])

      new_client = Client.update_middleware!(client, FirstMiddleware, fn _ -> ThirdMiddleware end)

      assert Client.middleware(new_client) == [ThirdMiddleware, SecondMiddleware, FirstMiddleware]
    end

    test "raises when target not found" do
      client = Tesla.client([FirstMiddleware])

      assert_raise ArgumentError, ~r/not found/, fn ->
        Client.update_middleware!(client, SecondMiddleware, fn m -> m end)
      end
    end

    test "preserves adapter" do
      adapter = Tesla.Adapter.Httpc
      client = Tesla.client([FirstMiddleware], adapter)

      new_client =
        Client.update_middleware!(client, FirstMiddleware, fn _ -> SecondMiddleware end)

      assert Client.adapter(new_client) == adapter
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

  describe "Inspect" do
    @secret "Bearer s3cret-token"

    defp secret_client do
      Tesla.client(
        [
          {Tesla.Middleware.BaseUrl, "https://api.example.com"},
          {Tesla.Middleware.Headers, [{"authorization", @secret}]},
          Tesla.Middleware.JSON,
          fn env, next -> Tesla.run(env, next) end
        ],
        {Tesla.Adapter.Httpc, [recv_timeout: 30_000]}
      )
    end

    defp with_inspect_mode(mode, fun) do
      previous = Application.get_env(:tesla, :inspect)
      Application.put_env(:tesla, :inspect, mode)

      try do
        fun.()
      after
        if previous,
          do: Application.put_env(:tesla, :inspect, previous),
          else: Application.delete_env(:tesla, :inspect)
      end
    end

    test "redacts middleware and adapter options by default, keeping module names" do
      printed = inspect(secret_client())

      refute printed =~ @secret
      refute printed =~ "api.example.com"
      refute printed =~ "recv_timeout"
      assert printed =~ "#Tesla.Client<"
      assert printed =~ "{Tesla.Middleware.BaseUrl, :redacted}"
      assert printed =~ "{Tesla.Middleware.Headers, :redacted}"
      assert printed =~ "Tesla.Middleware.JSON"
      assert printed =~ ":fn"
      assert printed =~ "adapter: {Tesla.Adapter.Httpc, :redacted}"
    end

    test "an env that embeds the client does not print the client's secrets" do
      client = Tesla.client([{Tesla.Middleware.Headers, [{"authorization", @secret}]}])

      env = %Tesla.Env{
        method: :get,
        url: "https://api.example.com/",
        status: 500,
        __client__: client
      }

      printed = inspect(env)

      refute printed =~ @secret
      assert printed =~ "__client__: #Tesla.Client<"
    end

    test "config :tesla, inspect: :full shows the options in their original form" do
      with_inspect_mode(:full, fn ->
        printed = inspect(secret_client())

        assert printed =~ @secret
        assert printed =~ ~s({Tesla.Middleware.BaseUrl, "https://api.example.com"})
        assert printed =~ "adapter: {Tesla.Adapter.Httpc, [recv_timeout: 30000]}"
      end)
    end

    test "renders an empty client" do
      assert inspect(%Tesla.Client{}) == "#Tesla.Client<adapter: nil, middleware: []>"
    end

    test "shows post middleware only when present" do
      client = %Tesla.Client{
        secret_client()
        | post: [{Tesla.Middleware.Logger, :call, [[level: :debug]]}]
      }

      assert inspect(client) =~ "post: [{Tesla.Middleware.Logger, :redacted}]"
    end
  end
end
