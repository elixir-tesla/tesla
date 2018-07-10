defmodule Tesla.Middleware.RetryTest do
  use ExUnit.Case, async: false

  defmodule LaggyAdapter do
    def start_link, do: Agent.start_link(fn -> 0 end, name: __MODULE__)

    def call(env, _opts) do
      Agent.get_and_update(__MODULE__, fn retries ->
        response =
          case env.url do
            "/ok" -> {:ok, env}
            "/maybe" when retries < 5 -> {:error, :econnrefused}
            "/maybe" -> {:ok, env}
            "/nope" -> {:error, :econnrefused}
          end

        {response, retries + 1}
      end)
    end
  end

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Retry, delay: 10, max_retries: 10

    adapter LaggyAdapter
  end

  defmodule Client2 do
    use Tesla

    plug Tesla.Middleware.Retry, delay: 10, max_retries: :infinity

    adapter LaggyAdapter
  end

  setup do
    {:ok, _} = LaggyAdapter.start_link()
    :ok
  end

  test "pass on successful request" do
    assert {:ok, %Tesla.Env{url: "/ok", method: :get}} = Client.get("/ok")
    assert {:ok, %Tesla.Env{url: "/ok", method: :get}} = Client2.get("/ok")
  end

  test "finally pass on laggy request" do
    assert {:ok, %Tesla.Env{url: "/maybe", method: :get}} = Client.get("/maybe")
    assert {:ok, %Tesla.Env{url: "/maybe", method: :get}} = Client2.get("/maybe")
  end

  test "raise if max_retries is exceeded" do
    assert {:error, :econnrefused} = Client.get("/nope")
  end

  defmodule DefunctClient do
    use Tesla

    plug Tesla.Middleware.Retry

    adapter fn _ -> raise "runtime-error" end
  end

  test "raise in case or unexpected error" do
    assert_raise RuntimeError, fn -> DefunctClient.get("/blow") end
  end
end
