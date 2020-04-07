defmodule Tesla.Middleware.FollowRedirectsTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.FollowRedirects

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "http://example.com/0" ->
            assert env.query == []
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

  test "drop the query" do
    assert {:ok, env} = Client.get("http://example.com/5", some_query: "params")
    assert env.query == []
  end

  defmodule CustomMaxRedirectsClient do
    use Tesla

    plug Tesla.Middleware.FollowRedirects, max_redirects: 1

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "http://example.com/0" ->
            assert env.query == []
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
            {307, [{"location", "http://example.com/#{next}"}], ""}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  alias CustomPreservesRequestClient, as: CPRClient

  test "Preserves original request for 307" do
    assert {:ok, env} =
             CPRClient.post(
               "http://example.com/1",
               "Body data",
               headers: [{"X-Custom-Header", "custom value"}]
             )

    assert env.method == :post
    assert env.body == "Body data"
    assert env.headers == [{"X-Custom-Header", "custom value"}]
  end

  describe "headers" do
    defp setup_client(_) do
      middleware = [Tesla.Middleware.FollowRedirects]

      adapter = fn
        %{url: "http://example.com/keep", headers: headers} = env ->
          send(self(), headers)

          {:ok,
           %{env | status: 301, headers: [{"location", "http://example.com/next"}], body: ""}}

        %{url: "http://example.com/drop", headers: headers} = env ->
          send(self(), headers)

          {:ok,
           %{env | status: 301, headers: [{"location", "http://example.net/next"}], body: ""}}

        %{url: "http://example.com/next", headers: headers} = env ->
          send(self(), headers)
          {:ok, %{env | status: 200, headers: [], body: "ok com"}}

        %{url: "http://example.net/next", headers: headers} = env ->
          send(self(), headers)
          {:ok, %{env | status: 200, headers: [], body: "ok net"}}
      end

      {:ok, client: Tesla.client(middleware, adapter)}
    end

    setup :setup_client

    test "Keep authorization header on redirect to the same domain", %{client: client} do
      assert {:ok, env} =
               Tesla.post(client, "http://example.com/keep", "",
                 headers: [
                   {"content-type", "text/plain"},
                   {"authorization", "Basic: secret"}
                 ]
               )

      # Initial request receives all headers
      assert_receive [
        {"content-type", "text/plain"},
        {"authorization", "Basic: secret"}
      ]

      # Next request also receives all headers
      assert_receive [
        {"content-type", "text/plain"},
        {"authorization", "Basic: secret"}
      ]
    end

    test "Strip authorization header on redirect to a different domain", %{client: client} do
      assert {:ok, env} =
               Tesla.post(client, "http://example.com/drop", "",
                 headers: [
                   {"content-type", "text/plain"},
                   {"authorization", "Basic: secret"}
                 ]
               )

      # Initial request receives all headers
      assert_receive [
        {"content-type", "text/plain"},
        {"authorization", "Basic: secret"}
      ]

      # Next request does not receive authorization header
      assert_receive [
        {"content-type", "text/plain"}
      ]
    end

    test "Keep custom host header on redirect to a different domain", %{client: client} do
      assert {:ok, env} =
               Tesla.post(client, "http://example.com/keep", "",
                 headers: [
                   {"host", "example.xyz"}
                 ]
               )

      # Initial request receives host header
      assert_receive [
        {"host", "example.xyz"}
      ]

      # Next request does not receive host header
      assert_receive [
        {"host", "example.xyz"}
      ]
    end

    test "Strip custom host header on redirect to a different domain", %{client: client} do
      assert {:ok, env} =
               Tesla.post(client, "http://example.com/drop", "",
                 headers: [
                   {"host", "example.xyz"}
                 ]
               )

      # Initial request receives host header
      assert_receive [
        {"host", "example.xyz"}
      ]

      # Next request does not receive host header
      assert_receive []
    end
  end
end
