defmodule RetryTest do
  use ExUnit.Case, async: false

  use Tesla.Middleware.TestCase, middleware: Tesla.Middleware.Retry

  defmodule LaggyAdapter do
    def start_link, do: Agent.start_link(fn -> 0 end, name: __MODULE__)

    def call(env, _opts) do
      Agent.get_and_update __MODULE__, fn retries ->
        response = case env.url do
          "/ok"                     -> env
          "/maybe" when retries < 5 -> {:error, :econnrefused}
          "/maybe"                  -> env
          "/nope"                   -> {:error, :econnrefused}
        end

        {response, retries + 1}
      end
    end
  end


  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Retry, delay: 10, max_retries: 10

    adapter LaggyAdapter
  end

  setup do
    {:ok, _} = LaggyAdapter.start_link
    :ok
  end

  test "pass on successful request" do
    assert %Tesla.Env{url: "/ok", method: :get} == Client.get("/ok")
  end

  test "finally pass on laggy request" do
    assert %Tesla.Env{url: "/maybe", method: :get} == Client.get("/maybe")
  end

  test "raise if max_retries is exceeded" do
    assert_raise Tesla.Error, fn -> Client.get("/nope") end
  end

end
