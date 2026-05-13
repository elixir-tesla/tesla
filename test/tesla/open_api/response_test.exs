defmodule Tesla.OpenAPI.ResponseTest do
  use ExUnit.Case, async: true

  defmodule Response do
    use Tesla.OpenAPI.Response
  end

  test "new/2 wraps typed response body" do
    env = %Tesla.Env{
      status: 200,
      headers: [{"content-type", "application/json"}]
    }

    assert Response.new(env, %{id: 42}) == %Response{
             status: 200,
             ok: true,
             headers: [{"content-type", "application/json"}],
             body: %{id: 42}
           }
  end

  test "new/2 marks non-2xx responses as not ok" do
    env = %Tesla.Env{
      status: 404,
      headers: [{"content-type", "application/json"}]
    }

    assert Response.new(env, %{error: "not_found"}) == %Response{
             status: 404,
             ok: false,
             headers: [{"content-type", "application/json"}],
             body: %{error: "not_found"}
           }
  end

  test "new/2 keeps the operation-selected response body" do
    assert %Response{status: 404, ok: false, body: nil} =
             Response.new(%Tesla.Env{status: 404}, nil)
  end

  test "new/2 treats 299 as ok and 300 as not ok" do
    assert %Response{ok: true} = Response.new(%Tesla.Env{status: 299}, nil)
    assert %Response{ok: false} = Response.new(%Tesla.Env{status: 300}, nil)
  end

  test "new/2 keeps ok unset when status is unset" do
    assert %Response{status: nil, ok: nil} = Response.new(%Tesla.Env{}, nil)
  end
end
