defmodule Tesla.Middleware.DecodeRelsTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.DecodeRels

    adapter fn env ->
      {:ok,
       case env.url do
         "/rels-with-no-quotes" ->
           Tesla.put_headers(env, [
             {"link", ~s(<https://api.github.com/resource?page=2>; rel=next,
               <https://api.github.com/resource?page=5>; rel=last)}
           ])

         "/rels" ->
           Tesla.put_headers(env, [
             {"link", ~s(<https://api.github.com/resource?page=2>; rel="next",
               <https://api.github.com/resource?page=5>; rel="last")}
           ])

         _ ->
           env
       end}
    end
  end

  test "decode rels" do
    assert {:ok, env} = Client.get("/rels")

    assert env.opts[:rels] == %{
             "next" => "https://api.github.com/resource?page=2",
             "last" => "https://api.github.com/resource?page=5"
           }

    assert {:ok, unquoted_env} = Client.get("/rels-with-no-quotes")

    assert unquoted_env.opts[:rels] == %{
             "next" => "https://api.github.com/resource?page=2",
             "last" => "https://api.github.com/resource?page=5"
           }
  end

  test "skip if no Link header" do
    assert {:ok, env} = Client.get("/")

    assert env.opts[:rels] == nil
  end
end
