defmodule EchoAdapter do
  def call(env) do
    env
  end
end

defmodule EchoClient do
  use Tesla

  adapter EchoAdapter
end

defmodule TeslaTest do
  use ExUnit.Case

  test "get" do
    env = EchoClient.get("/foo")
    assert env.method == :get
  end

  test "post" do
    env = EchoClient.post("/foo")
    assert env.method == :post
  end
end
