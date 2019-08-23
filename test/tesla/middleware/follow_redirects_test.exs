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

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "redirects if default max redirects isn't exceeded" do
    assert {:ok, env} = Client.get("http://example.com/5")
    assert env.status == 200
  end

  test "raise error when redirect default max redirects is exceeded" do
    assert {:error, {Tesla.Middleware.FollowRedirects, :too_many_redirects}} ==
             Client.get("http://example.com/6")
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

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  alias CustomMaxRedirectsClient, as: CMRClient

  test "redirects if custom max redirects isn't exceeded" do
    assert {:ok, env} = CMRClient.get("http://example.com/1")
    assert env.status == 200
  end

  test "raise error when custom max redirects is exceeded" do
    assert {:error, {Tesla.Middleware.FollowRedirects, :too_many_redirects}} ==
             CMRClient.get("http://example.com/2")
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

          "https://example.com/one/two" ->
            {301, [{"location", "three"}], ""}

          "https://example.com/one/three" ->
            {200, [{"content-type", "text/plain"}], "foo bar baz"}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  alias RelativeLocationClient, as: RLClient

  test "supports relative address in location header" do
    assert {:ok, env} = RLClient.get("http://example.com")
    assert env.status == 200
  end

  test "doesn't create double slashes inside new url" do
    assert {:ok, env} = RLClient.get("https://example.com/")
    assert env.url == "https://example.com/pl"
  end

  test "rewrites URLs to their root" do
    assert {:ok, env} = RLClient.get("https://example.com/article")
    assert env.url == "https://example.com/pl"
  end

  test "rewrites URLs relative to the original URL" do
    assert {:ok, env} = RLClient.get("https://example.com/one/two")
    assert env.url == "https://example.com/one/three"
  end

  defmodule CustomRewriteMethodClient do
    use Tesla

    plug Tesla.Middleware.FollowRedirects

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "http://example.com/0" ->
            {200, [{"content-type", "text/plain"}], "foo bar"}

          "http://example.com/" <> n ->
            next = String.to_integer(n) - 1
            {303, [{"location", "http://example.com/#{next}"}], ""}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  alias CustomRewriteMethodClient, as: CRMClient

  test "rewrites method to get for 303 requests" do
    assert {:ok, env} = CRMClient.post("http://example.com/1", "")
    assert env.method == :get
  end

  defmodule CustomPreservesRequestClient do
    use Tesla

    plug Tesla.Middleware.FollowRedirects

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "http://example.com/0" ->
            {200, env.headers, env.body}

          "http://example.com/" <> n ->
            next = String.to_integer(n) - 1
            {301, [{"location", "http://example.com/#{next}"}], ""}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  alias CustomPreservesRequestClient, as: CPRClient

  test "Preserves original request" do
    assert {:ok, env} =
             CPRClient.post(
               "http://example.com/1",
               "Body data",
               headers: [{"X-Custom-Header", "custom value"}]
             )

    assert env.body == "Body data"
    assert env.headers == [{"X-Custom-Header", "custom value"}]
  end
end
