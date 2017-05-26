defmodule FollowRedirectsTest do
  use ExUnit.Case

  use Tesla.Middleware.TestCase, middleware: Tesla.Middleware.FollowRedirects

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.FollowRedirects

    adapter fn (env) ->
      {status, headers, body} = case env.url do
        "/0" ->
          {200, %{'Content-Type' => 'text/plain'}, "foo bar"}
        "/" <> n ->
          next = String.to_integer(n) - 1
          {301, %{'Location' => '/#{next}'}, ""}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "redirects if default max redirects isn't exceeded" do
    assert Client.get("/5").status == 200
  end

  test "error when redirect default max redirects is exceeded" do
    assert {:error, :too_many_redirects} = Client.get("/6")
  end

  defmodule CustomMaxRedirectsClient do
    use Tesla

    plug Tesla.Middleware.FollowRedirects, max_redirects: 1

    adapter fn (env) ->
      {status, headers, body} = case env.url do
        "/0" ->
          {200, %{'Content-Type' => 'text/plain'}, "foo bar"}
        "/" <> n ->
          next = String.to_integer(n) - 1
          {301, %{'Location' => '/#{next}'}, ""}
      end

      %{env | status: status, headers: headers, body: body}
    end
  end

  alias CustomMaxRedirectsClient, as: CMRClient

  test "redirects if custom max redirects isn't exceeded" do
    assert CMRClient.get("/1").status == 200
  end

  test "error when custom max redirects is exceeded" do
    assert {:error, :too_many_redirects} = CMRClient.get("/2")
  end

end
