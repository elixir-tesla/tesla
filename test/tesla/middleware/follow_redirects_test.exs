defmodule Tesla.Middleware.FollowRedirectsTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.FollowRedirects

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "http://example.com/0" ->
            {200, [{"content-type", "text/plain"}], "foo bar"}

          "http://example.com/" <> n ->
            next = String.to_integer(n) - 1
            {301, [{"location", "http://example.com/#{next}"}], ""}
        end

      %{env | status: status, headers: headers, body: body}
    end
  end

  test "redirects if default max redirects isn't exceeded" do
    assert Client.get("http://example.com/5").status == 200
  end

  test "raise error when redirect default max redirects is exceeded" do
    assert_raise(Tesla.Error, "too many redirects", fn -> Client.get("http://example.com/6") end)
  end

  defmodule CustomMaxRedirectsClient do
    use Tesla

    plug Tesla.Middleware.FollowRedirects, max_redirects: 1

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "http://example.com/0" ->
            {200, [{"content-type", "text/plain"}], "foo bar"}

          "http://example.com/" <> n ->
            next = String.to_integer(n) - 1
            {301, [{"location", "http://example.com/#{next}"}], ""}
        end

      %{env | status: status, headers: headers, body: body}
    end
  end

  alias CustomMaxRedirectsClient, as: CMRClient

  test "redirects if custom max redirects isn't exceeded" do
    assert CMRClient.get("http://example.com/1").status == 200
  end

  test "raise error when custom max redirects is exceeded" do
    assert_raise(Tesla.Error, "too many redirects", fn ->
      CMRClient.get("http://example.com/2")
    end)
  end

  defmodule RelativeLocationClient do
    use Tesla

    plug Tesla.Middleware.FollowRedirects

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "https://example.com/pl" ->
            {200, [{"content-type", "text/plain"}], "foo bar"}

          "http://example.com" ->
            {301, [{"location", "https://example.com"}], ""}

          "https://example.com" ->
            {301, [{"location", "/pl"}], ""}

          "https://example.com/" ->
            {301, [{"location", "/pl"}], ""}

          "https://example.com/article" ->
            {301, [{"location", "/pl"}], ""}
        end

      %{env | status: status, headers: headers, body: body}
    end
  end

  alias RelativeLocationClient, as: RLClient

  test "supports relative address in location header" do
    assert RLClient.get("http://example.com").status == 200
  end

  test "doesn't create double slashes inside new url" do
    assert RLClient.get("https://example.com/").url == "https://example.com/pl"
  end

  test "rewrites URLs to their root" do
    assert RLClient.get("https://example.com/article").url == "https://example.com/pl"
  end
end
