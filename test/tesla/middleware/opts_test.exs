defmodule Tesla.Middleware.OptsTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla
    @api_key "some_key"

    plug Tesla.Middleware.Opts, attr: %{"Authorization" => @api_key}
    plug Tesla.Middleware.Opts, list: ["a", "b", "c"], int: 123
    plug Tesla.Middleware.Opts, fun: fn x -> x * 2 end

    adapter fn env -> env end
  end

  test "apply middleware options" do
    env = Client.get("/")

    assert env.opts[:attr] == %{"Authorization" => "some_key"}
    assert env.opts[:int] == 123
    assert env.opts[:list] == ["a", "b", "c"]
    assert env.opts[:fun].(4) == 8
  end
end
