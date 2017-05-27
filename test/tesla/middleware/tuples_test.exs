defmodule TuplesTest do
  use ExUnit.Case, async: false

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Tuples
    plug Tesla.Middleware.JSON

    adapter fn env ->
      case env.url do
        "/ok"            -> env
        "/econnrefused"  -> {:error, :econnrefused}
      end
    end
  end

  test "return {:ok, env} for successful transaction" do
    assert {:ok, %Tesla.Env{}} = Client.get("/ok")
  end

  test "return {:error, reason} for unsuccessful transaction" do
    assert {:error, %Tesla.Error{}} = Client.get("/econnrefused")
  end
end
