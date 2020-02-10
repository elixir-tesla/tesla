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

  defmodule ClientWithCustomSetup do
    use Tesla

    plug Tesla.Middleware.Fuse,
      keep_original_error: true,
      should_melt: fn
        {:ok, %{status: status}} when status in [504] -> true
        {:ok, _} -> false
        {:error, _} -> true
      end

    plug Report

    adapter fn env ->
      case env.url do
        "/ok" ->
          {:ok, env}

        "/error_500" ->
          {:ok, %{env | status: 500}}

        "/error_504" ->
          {:ok, %{env | status: 504}}

        "/unavailable" ->
          {:error, :econnrefused}
      end
    end
  end

  setup do
    Application.ensure_all_started(:fuse)
    :fuse.reset(Client)
    :fuse.reset(ClientWithCustomSetup)

    :ok
  end

  test "regular endpoint" do
    assert {:ok, %Tesla.Env{url: "/ok"}} = Client.get("/ok")
  end

  test "custom should_melt function - not melting 500" do
    assert {:ok, %Tesla.Env{status: 500}} = ClientWithCustomSetup.get("/error_500")
    assert_receive :request_made
    assert {:ok, %Tesla.Env{status: 500}} = ClientWithCustomSetup.get("/error_500")
    assert_receive :request_made
    assert {:ok, %Tesla.Env{status: 500}} = ClientWithCustomSetup.get("/error_500")
    assert_receive :request_made

    assert {:ok, %Tesla.Env{status: 500}} = ClientWithCustomSetup.get("/error_500")
    assert_receive :request_made
    assert {:ok, %Tesla.Env{status: 500}} = ClientWithCustomSetup.get("/error_500")
    assert_receive :request_made
  end

  test "custom should_melt function - melting 504" do
    assert {:ok, %Tesla.Env{status: 504}} = ClientWithCustomSetup.get("/error_504")
    assert_receive :request_made
    assert {:ok, %Tesla.Env{status: 504}} = ClientWithCustomSetup.get("/error_504")
    assert_receive :request_made
    assert {:ok, %Tesla.Env{status: 504}} = ClientWithCustomSetup.get("/error_504")
    assert_receive :request_made

    assert {:error, :unavailable} = ClientWithCustomSetup.get("/error_504")
    refute_receive :request_made
    assert {:error, :unavailable} = ClientWithCustomSetup.get("/error_504")
    refute_receive :request_made
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
