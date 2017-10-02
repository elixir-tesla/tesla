defmodule Tesla.Middleware.DecodeRelsTest do
  use ExUnit.Case

  alias Tesla.Env

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.DecodeRels

    adapter fn _env ->
      %Env{headers: %{
        "Link" => ~s(<https://api.github.com/resource?page=2>; rel="next",
        <https://api.github.com/resource?page=5>; rel="last")
      }}
    end
  end

  test "deocde rels" do
    env = Client.get("/")

    assert env.opts[:rels] == %{
      "next" => "https://api.github.com/resource?page=2",
      "last" => "https://api.github.com/resource?page=5"
    }
  end
end
