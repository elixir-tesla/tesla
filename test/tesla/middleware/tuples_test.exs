defmodule Tesla.Middleware.TuplesTest do
  use ExUnit.Case, async: false

  defmodule(Custom1, do: defexception(message: "Custom 1"))
  defmodule(Custom2, do: defexception(message: "Custom 2"))

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Tuples, rescue_errors: [Custom1]
    plug Tesla.Middleware.JSON

    adapter fn env ->
      case env.url do
        "/ok" -> env
        "/econnrefused" -> {:error, :econnrefused}
        "/custom-1" -> raise %Custom1{}
        "/custom-2" -> raise %Custom2{}
      end
    end
  end

  defmodule DefaultClient do
    use Tesla

    plug Tesla.Middleware.Tuples

    adapter fn _ -> raise %Custom1{} end
  end

  test "return {:ok, env} for successful transaction" do
    assert {:ok, %Tesla.Env{}} = Client.get("/ok")
  end

  test "return {:error, reason} for unsuccessful transaction" do
    assert {:error, %Tesla.Error{}} = Client.get("/econnrefused")
  end

  test "rescue listed custom exception" do
    assert {:error, %Custom1{}} = Client.get("/custom-1")
  end

  test "do not rescue not-listed custom exception" do
    assert catch_error(Client.get("/custom-2"))
    assert catch_error(DefaultClient.get("/"))
  end
end
