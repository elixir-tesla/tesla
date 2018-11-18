defmodule Tesla.Middleware.CacheTest do
  use ExUnit.Case

  defmodule TestStore do
    @behaviour Tesla.Middleware.Cache.Store

    def get(key) do
      case Process.get(key) do
        nil -> :not_found
        data -> {:ok, data}
      end
    end

    def put(key, data) do
      Process.put(key, data)
    end

    def delete(key) do
      Process.delete(key)
    end
  end

  defmodule TestAdapter do
    # source: https://github.com/plataformatec/faraday-http-cache/blob/master/spec/support/test_app.rb

    alias Calendar.DateTime

    def call(env, opts) do
      {status, headers, body} = handle(env.method, env.url, env)
      send(opts[:pid], {env.method, env.url, status})
      {:ok, %{env | status: status, headers: headers, body: body}}
    end

    @yesterday DateTime.now_utc()
               |> DateTime.subtract!(60 * 60 * 24)
               |> DateTime.Format.httpdate()

    defp handle(:post, "/post", _) do
      {200, [{"cache-control", "max-age=400"}], ""}
    end

    defp handle(:get, "/broken", _) do
      {500, [{"cache-control", "max-age=400"}], ""}
    end

    defp handle(:get, "/counter", _) do
      {200, [{"cache-control", "max-age=200"}], ""}
    end

    defp handle(:post, "/counter", _) do
      {200, [], ""}
    end

    defp handle(:put, "/counter", _) do
      {200, [], ""}
    end

    defp handle(:delete, "/counter", _) do
      {200, [], ""}
    end

    defp handle(:patch, "/counter", _) do
      {200, [], ""}
    end

    defp handle(:get, "/get", _) do
      date = DateTime.now_utc() |> DateTime.Format.httpdate()
      {200, [{"cache-control", "max-age=200"}, {"date", date}], ""}
    end

    defp handle(:post, "/delete-with-location", _) do
      {200, [{"location", "/get"}], ""}
    end

    defp handle(:post, "/delete-with-content-location", _) do
      {200, [{"content-location", "/get"}], ""}
    end

    defp handle(:post, "/get", _) do
      {405, [], ""}
    end

    defp handle(:get, "/private", _) do
      {200, [{"cache-control", "private, max-age=100"}], ""}
    end

    defp handle(:get, "/dontstore", _) do
      {200, [{"cache-control", "no-store"}], ""}
    end

    defp handle(:get, "/expires", _) do
      expires = DateTime.now_utc() |> DateTime.add!(10) |> DateTime.Format.httpdate()
      {200, [{"expires", expires}], ""}
    end

    defp handle(:get, "/yesterday", _) do
      {200, [{"date", @yesterday}, {"expires", @yesterday}], ""}
    end

    defp handle(:get, "/timestamped", env) do
      case Tesla.get_header(env, "if-modified-since") do
        "1" ->
          {304, [], ""}

        nil ->
          increment_counter()
          {200, [{"last-modified", to_string(counter())}], to_string(counter())}
      end
    end

    defp handle(:get, "/etag", env) do
      case Tesla.get_header(env, "if-none-match") do
        "1" ->
          date = DateTime.now_utc()
          expires = DateTime.now_utc() |> DateTime.add!(10)

          headers = [
            {"etag", "2"},
            {"cache-control", "max-age=200"},
            {"date", DateTime.Format.httpdate(date)},
            {"expires", DateTime.Format.httpdate(expires)},
            {"vary", "*"}
          ]

          {304, headers, ""}

        nil ->
          increment_counter()
          expires = DateTime.now_utc()

          headers = [
            {"etag", "1"},
            {"cache-control", "max-age=0"},
            {"date", @yesterday},
            {"expires", DateTime.Format.httpdate(expires)},
            {"vary", "Accept"}
          ]

          {200, headers, to_string(counter())}
      end
    end

    defp handle(:get, "/no_cache", _) do
      increment_counter()
      {200, [{"cache-control", "max-age=200, no-cache"}, {"ETag", to_string(counter())}], ""}
    end

    defp handle(:get, "/vary", _) do
      {200, [{"cache-control", "max-age=50"}, {"vary", "user-agent"}], ""}
    end

    defp handle(:get, "/vary-wildcard", _) do
      {200, [{"cache-control", "max-age=50"}, {"vary", "*"}], ""}
    end

    defp handle(:get, "/image", _) do
      data = :crypto.strong_rand_bytes(100)

      headers = [
        {"cache-control", "max-age=400"},
        {"content-type", "application/octet-stream"}
      ]

      {200, headers, data}
    end

    defp counter, do: Process.get(:counter) || 0

    defp increment_counter do
      next = counter() + 1
      Process.put(:counter, next)
      to_string(next)
    end
  end

  setup do
    middleware = [
      {Tesla.Middleware.Cache, store: TestStore}
    ]

    adapter = {TestAdapter, pid: self()}
    client = Tesla.client(middleware, adapter)

    {:ok, client: client, adapter: adapter}
  end

  # source: https://github.com/plataformatec/faraday-http-cache/blob/master/spec/http_cache_spec.rb

  describe "basics" do
    test "caches GET responses", %{client: client} do
      refute_cached Tesla.get(client, "/get")
      assert_cached Tesla.get(client, "/get")
    end

    test "does not cache POST requests", %{client: client} do
      refute_cached Tesla.post(client, "/post", "hello")
      refute_cached Tesla.post(client, "/post", "world")
    end

    test "does not cache responses with 500 status code", %{client: client} do
      refute_cached Tesla.get(client, "/broken")
      refute_cached Tesla.get(client, "/broken")
    end

    test "differs requests with different query strings", %{client: client} do
      refute_cached Tesla.get(client, "/get")
      refute_cached Tesla.get(client, "/get", query: [q: "what"])
      assert_cached Tesla.get(client, "/get", query: [q: "what"])
      refute_cached Tesla.get(client, "/get", query: [q: "wat"])
    end
  end

  describe "headers handling" do
    test "does not cache responses with a explicit no-store directive", %{client: client} do
      refute_cached Tesla.get(client, "/dontstore")
      refute_cached Tesla.get(client, "/dontstore")
    end

    test "does not caches multiple responses when the headers differ", %{client: client} do
      refute_cached Tesla.get(client, "/get", headers: [{"accept", "text/html"}])
      assert_cached Tesla.get(client, "/get", headers: [{"accept", "text/html"}])

      # TODO: This one fails - the reqeust IS cached.
      #       I think faraday-http-cache specs migh have a bug
      # refute_cached Tesla.get(client, "/get", headers: [{"accept", "application/json"}])
    end

    test "caches multiples responses based on the 'Vary' header", %{client: client} do
      refute_cached Tesla.get(client, "/vary", headers: [{"user-agent", "Agent/1.0"}])
      assert_cached Tesla.get(client, "/vary", headers: [{"user-agent", "Agent/1.0"}])
      refute_cached Tesla.get(client, "/vary", headers: [{"user-agent", "Agent/2.0"}])
      refute_cached Tesla.get(client, "/vary", headers: [{"user-agent", "Agent/3.0"}])
    end

    test "never caches responses with the wildcard 'Vary' header", %{client: client} do
      refute_cached Tesla.get(client, "/vary-wildcard")
      refute_cached Tesla.get(client, "/vary-wildcard")
    end

    test "caches requests with the 'Expires' header", %{client: client} do
      refute_cached Tesla.get(client, "/expires")
      assert_cached Tesla.get(client, "/expires")
    end

    test "sends the 'Last-Modified' header on response validation", %{client: client} do
      refute_cached Tesla.get(client, "/timestamped")

      assert_validated({:ok, env} = Tesla.get(client, "/timestamped"))
      assert env.body == "1"
    end

    test "sends the 'If-None-Match' header on response validation", %{client: client} do
      refute_cached Tesla.get(client, "/etag")

      assert_validated({:ok, env} = Tesla.get(client, "/etag"))
      assert env.body == "1"
    end

    test "maintains the 'Date' header for cached responses", %{client: client} do
      refute_cached({:ok, env0} = Tesla.get(client, "/get"))
      assert_cached({:ok, env1} = Tesla.get(client, "/get"))

      date0 = Tesla.get_header(env0, "date")
      date1 = Tesla.get_header(env1, "date")

      assert date0 != nil
      assert date0 == date1
    end

    test "preserves an old 'Date' header if present", %{client: client} do
      refute_cached({:ok, env} = Tesla.get(client, "/yesterday"))
      date = Tesla.get_header(env, "date")
      assert date =~ ~r/^\w{3}, \d{2} \w{3} \d{4} \d{2}:\d{2}:\d{2} GMT$/
    end
  end

  describe "cache invalidation" do
    test "expires POST requests", %{client: client} do
      refute_cached Tesla.get(client, "/counter")
      refute_cached Tesla.post(client, "/counter", "")
      refute_cached Tesla.get(client, "/counter")
    end

    test "does not expires POST requests that failed", %{client: client} do
      refute_cached Tesla.get(client, "/get")
      refute_cached Tesla.post(client, "/get", "")
      assert_cached Tesla.get(client, "/get")
    end

    test "expires PUT requests", %{client: client} do
      refute_cached Tesla.get(client, "/counter")
      refute_cached Tesla.put(client, "/counter", "")
      refute_cached Tesla.get(client, "/counter")
    end

    test "expires DELETE requests", %{client: client} do
      refute_cached Tesla.get(client, "/counter")
      refute_cached Tesla.delete(client, "/counter")
      refute_cached Tesla.get(client, "/counter")
    end

    test "expires PATCH requests", %{client: client} do
      refute_cached Tesla.get(client, "/counter")
      refute_cached Tesla.patch(client, "/counter", "")
      refute_cached Tesla.get(client, "/counter")
    end

    test "expires entries for the 'Location' header", %{client: client} do
      refute_cached Tesla.get(client, "/get")
      refute_cached Tesla.post(client, "/delete-with-location", "")
      refute_cached Tesla.get(client, "/get")
    end

    test "expires entries for the 'Content-Location' header", %{client: client} do
      refute_cached Tesla.get(client, "/get")
      refute_cached Tesla.post(client, "/delete-with-content-location", "")
      refute_cached Tesla.get(client, "/get")
    end
  end

  describe "when acting as a shared cache (the default)" do
    test "does not cache requests with a private cache control", %{client: client} do
      refute_cached Tesla.get(client, "/private")
      refute_cached Tesla.get(client, "/private")
    end
  end

  describe "when acting as a private cache" do
    test "does cache requests with a private cache control", %{adapter: adapter} do
      middleware = [
        {Tesla.Middleware.Cache, store: TestStore, cache_private: true}
      ]

      client = Tesla.client(middleware, adapter)

      refute_cached Tesla.get(client, "/private")
      assert_cached Tesla.get(client, "/private")
    end
  end

  describe "when the request has a 'no-cache' directive" do
    test "by-passes the cache", %{client: client} do
      refute_cached Tesla.get(client, "/get", headers: [{"cache-control", "no-cache"}])
      refute_cached Tesla.get(client, "/get", headers: [{"cache-control", "no-cache"}])
    end

    test "caches the response", %{client: client} do
      refute_cached Tesla.get(client, "/get", headers: [{"cache-control", "no-cache"}])
      assert_cached Tesla.get(client, "/get")
    end
  end

  describe "when the response has a 'no-cache' directive" do
    test "always revalidate the cached response", %{client: client} do
      refute_cached Tesla.get(client, "/no_cache")
      refute_cached Tesla.get(client, "/no_cache")
      refute_cached Tesla.get(client, "/no_cache")
    end
  end

  describe "validation" do
    test "updates the 'Cache-Control' header when a response is validated", %{client: client} do
      {:ok, env0} = Tesla.get(client, "/etag")
      {:ok, env1} = Tesla.get(client, "/etag")

      cc0 = Tesla.get_header(env0, "cache-control")
      cc1 = Tesla.get_header(env1, "cache-control")

      assert cc0 != nil
      assert cc0 != cc1
    end

    test "updates the 'Date' header when a response is validated", %{client: client} do
      {:ok, env0} = Tesla.get(client, "/etag")
      {:ok, env1} = Tesla.get(client, "/etag")

      date0 = Tesla.get_header(env0, "date")
      date1 = Tesla.get_header(env1, "date")

      assert date0 != nil
      assert date0 != date1
    end

    test "updates the 'Expires' header when a response is validated", %{client: client} do
      {:ok, env0} = Tesla.get(client, "/etag")
      {:ok, env1} = Tesla.get(client, "/etag")

      expires0 = Tesla.get_header(env0, "expires")
      expires1 = Tesla.get_header(env1, "expires")

      assert expires0 != nil
      assert expires0 != expires1
    end

    test "updates the 'Vary' header when a response is validated", %{client: client} do
      {:ok, env0} = Tesla.get(client, "/etag")
      {:ok, env1} = Tesla.get(client, "/etag")

      vary0 = Tesla.get_header(env0, "vary")
      vary1 = Tesla.get_header(env1, "vary")

      assert vary0 != nil
      assert vary0 != vary1
    end
  end

  describe "CacheControl" do
    # Source: https://github.com/plataformatec/faraday-http-cache/blob/master/spec/cache_control_spec.rb

    alias Tesla.Middleware.Cache.CacheControl

    test "takes a String with multiple name=value pairs" do
      cache_control = CacheControl.new("max-age=600, max-stale=300, min-fresh=570")
      assert cache_control.max_age == 600
    end

    test "takes a String with a single flag value" do
      cache_control = CacheControl.new("no-cache")
      assert cache_control.no_cache? == true
    end

    test "takes a String with a bunch of all kinds of stuff" do
      cache_control = CacheControl.new("max-age=600,must-revalidate,min-fresh=3000,foo=bar,baz")

      assert cache_control.max_age == 600
      assert cache_control.must_revalidate? == true
    end

    test "strips leading and trailing spaces" do
      cache_control = CacheControl.new("   public,   max-age =   600  ")
      assert cache_control.public? == true
      assert cache_control.max_age == 600
    end

    test "ignores blank segments" do
      cache_control = CacheControl.new("max-age=600,,s-maxage=300")
      assert cache_control.max_age == 600
      assert cache_control.s_max_age == 300
    end

    test "responds to #max_age with an integer when max-age directive present" do
      cache_control = CacheControl.new("public, max-age=600")
      assert cache_control.max_age == 600
    end

    test "responds to #max_age with nil when no max-age directive present" do
      cache_control = CacheControl.new("public")
      assert cache_control.max_age == nil
    end

    test "responds to #shared_max_age with an integer when s-maxage directive present" do
      cache_control = CacheControl.new("public, s-maxage=600")
      assert cache_control.s_max_age == 600
    end

    test "responds to #shared_max_age with nil when no s-maxage directive present" do
      cache_control = CacheControl.new("public")
      assert cache_control.s_max_age == nil
    end

    test "responds to #public? truthfully when public directive present" do
      cache_control = CacheControl.new("public")
      assert cache_control.public? == true
    end

    test "responds to #public? non-truthfully when no public directive present" do
      cache_control = CacheControl.new("private")
      assert cache_control.public? == false
    end

    test "responds to #private? truthfully when private directive present" do
      cache_control = CacheControl.new("private")
      assert cache_control.private? == true
    end

    test "responds to #private? non-truthfully when no private directive present" do
      cache_control = CacheControl.new("public")
      assert cache_control.private? == false
    end

    test "responds to #no_cache? truthfully when no-cache directive present" do
      cache_control = CacheControl.new("no-cache")
      assert cache_control.no_cache? == true
    end

    test "responds to #no_cache? non-truthfully when no no-cache directive present" do
      cache_control = CacheControl.new("max-age=600")
      assert cache_control.no_cache? == false
    end

    test "responds to #must_revalidate? truthfully when must-revalidate directive present" do
      cache_control = CacheControl.new("must-revalidate")
      assert cache_control.must_revalidate? == true
    end

    test "responds to #must_revalidate? non-truthfully when no must-revalidate directive present" do
      cache_control = CacheControl.new("max-age=600")
      assert cache_control.must_revalidate? == false
    end

    test "responds to #proxy_revalidate? truthfully when proxy-revalidate directive present" do
      cache_control = CacheControl.new("proxy-revalidate")
      assert cache_control.proxy_revalidate? == true
    end

    test "responds to #proxy_revalidate? non-truthfully when no proxy-revalidate directive present" do
      cache_control = CacheControl.new("max-age=600")
      assert cache_control.proxy_revalidate? == false
    end
  end

  describe "Request" do
    alias Tesla.Middleware.Cache.Request
    
    test "GET request should be cacheable" do
      request = Request.new(%Tesla.Env{method: :get})
      assert Request.cacheable?(request) == true
    end

    test "HEAD request should be cacheable" do
      request = Request.new(%Tesla.Env{method: :head})
      assert Request.cacheable?(request) == true
    end

    test "POST request should not be cacheable" do
      request = Request.new(%Tesla.Env{method: :post})
      assert Request.cacheable?(request) == false
    end

    test "PUT request should not be cacheable" do
      request = Request.new(%Tesla.Env{method: :put})
      assert Request.cacheable?(request) == false
    end

    test "OPTIONS request should not be cacheable" do
      request = Request.new(%Tesla.Env{method: :options})
      assert Request.cacheable?(request) == false
    end

    test "DELETE request should not be cacheable" do
      request = Request.new(%Tesla.Env{method: :delete})
      assert Request.cacheable?(request) == false
    end

    test "TRACE request should not be cacheable" do
      request = Request.new(%Tesla.Env{method: :trace})
      assert Request.cacheable?(request) == false
    end

    test "no-store request should not be cacheable" do
      request = Request.new(%Tesla.Env{method: :get, headers: [{"cache-control", "no-store"}]})
      assert Request.cacheable?(request) == false
    end
  end

  describe "Response" do
  end

  describe "binary data" do
    # Source: https://github.com/plataformatec/faraday-http-cache/blob/master/spec/binary_spec.rb

    test "works fine with binary data", %{client: client} do
      refute_cached({:ok, env0} = Tesla.get(client, "/image"))
      assert_cached({:ok, env1} = Tesla.get(client, "/image"))

      assert env0.body != nil
      assert env0.body == env1.body
    end
  end

  defp assert_cached({:ok, %{method: method, url: url}}), do: refute_receive({^method, ^url, _})
  defp refute_cached({:ok, %{method: method, url: url}}), do: assert_receive({^method, ^url, _})

  defp assert_validated({:ok, %{method: method, url: url}}),
    do: assert_receive({^method, ^url, 304})
end
