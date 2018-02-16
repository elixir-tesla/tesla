defmodule Tesla.Middleware.FuseTest do
  use ExUnit.Case, async: false

  defmodule Report do
    def call(env, next, _) do
      send(self(), :request_made)
      Tesla.run(env, next)
    end
  end

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Fuse
    plug Report

    adapter fn env ->
      case env.url do
        "/ok" ->
          {:ok, env}

        "/unavailable" ->
          {:error, :econnrefused}
      end
    end
  end

  setup do
    Application.ensure_all_started(:fuse)
    :fuse.reset(Client)

    :ok
  end

  test "regular endpoint" do
    assert {:ok, %Tesla.Env{url: "/ok"}} = Client.get("/ok")
  end

  test "unavailable endpoint" do
    assert {:error, :unavailable} = Client.get("/unavailable")
    assert_receive :request_made
    assert {:error, :unavailable} = Client.get("/unavailable")
    assert_receive :request_made
    assert {:error, :unavailable} = Client.get("/unavailable")
    assert_receive :request_made

    assert {:error, :unavailable} = Client.get("/unavailable")
    refute_receive :request_made
    assert {:error, :unavailable} = Client.get("/unavailable")
    refute_receive :request_made
  end
end
