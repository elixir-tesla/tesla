defmodule EchoAdapter do
  def call(env) do
    env
  end
end

defmodule EchoClient do
  use Tesla

  adapter EchoAdapter
end

defmodule PoliteMiddleware do
  def call(env, run, []) do
    run.(%{env | url: (env.url <> "/please")})
  end
end

defmodule AngryMiddleware do
  def call(env, run, msg) do
    run.(%{env | url: env.url <> "/" <> msg})
  end
end

defmodule PoliteClient do
  use Tesla

  with PoliteMiddleware

  adapter EchoAdapter
end

defmodule AngryClient do
  use Tesla

  with AngryMiddleware, "booo"

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

  test "simple middleware" do
    env = PoliteClient.get("/foo")
    assert env.url == "/foo/please"
  end

  test "middleware with options" do
    env = AngryClient.get("/foo")
    assert env.url == "/foo/booo"
  end
end
