defmodule Tesla.Adapter.TestCase do
  @http_url   "http://localhost:#{Application.get_env(:httparrot, :http_port)}"
  @https_url  "https://httpbin.org"

  def http_url,   do: @http_url
  def https_url,  do: @https_url
end

defmodule Tesla.Adapter.TestCase.Basic do
  defmacro __using__([adapter: adapter]) do
    quote do
      defmodule B.Client do
        use Tesla

        adapter unquote(adapter)
      end

      import Tesla.Adapter.TestCase, only: [http_url: 0]
      require Tesla

      setup do
        {adapter, _} = B.Client.__adapter__
        {:ok, adapter: adapter}
      end

      test "basic head request" do
        response = B.Client.head("#{http_url()}/ip")
        assert response.status == 200
      end

      test "basic get request" do
        response = B.Client.get("#{http_url()}/ip")
        assert response.status == 200
      end

      test "basic post request" do
        response = B.Client.post("#{http_url()}/post", "some-post-data", headers: %{"Content-Type" => "text/plain"})
        assert response.status == 200
        assert response.headers["content-type"] == "application/json"
        assert Regex.match?(~r/some-post-data/, response.body)
      end

      test "passing query params" do
        client = Tesla.build_client([{Tesla.Middleware.JSON, nil}])
        response = client |> B.Client.get("#{http_url()}/get", query: [
          page: 1, sort: "desc",
          status: ["a", "b", "c"],
          user: [name: "Jon", age: 20]
        ])

        args = response.body["args"]

        assert args["page"] == "1"
        assert args["sort"] == "desc"
        assert args["status[]"]   == ["a", "b", "c"]
        assert args["user[name]"] == "Jon"
        assert args["user[age]"]  == "20"
      end

      test "error: normalized connection refused error", %{adapter: adapter} do
        assert {:error, :econnrefused} == adapter.call(%Tesla.Env{url: "http://localhost:1234"}, [])
      end

      test "error: connection refused" do
        assert_raise Tesla.Error, fn ->
          response = B.Client.get("http://localhost:1234")
        end
      end
    end
  end
end

defmodule Tesla.Adapter.TestCase.StreamRequestBody do
  defmacro __using__([adapter: adapter]) do
    quote do
      defmodule S.Client do
        use Tesla

        adapter unquote(adapter)
      end

      import Tesla.Adapter.TestCase, only: [http_url: 0]

      test "stream request body: Stream.map" do
        body = (1..5) |> Stream.map(&to_string/1)
        response = S.Client.post("#{http_url()}/post", body, headers: %{"Content-Type" => "text/plain"})
        assert response.status == 200
        assert Regex.match?(~r/12345/, to_string(response.body))
      end

      test "stream request body: Stream.unfold" do
        body = Stream.unfold(5, fn 0 -> nil; n -> {n,n-1} end)
        |> Stream.map(&to_string/1)
        response = S.Client.post("#{http_url()}/post", body, headers: %{"Content-Type" => "text/plain"})

        assert response.status == 200
        assert Regex.match?(~r/54321/, to_string(response.body))
      end
    end
  end
end

defmodule Tesla.Adapter.TestCase.SSL do
  defmacro __using__([adapter: adapter]) do
    quote do
      defmodule SSL.Client do
        use Tesla

        adapter unquote(adapter)
      end

      import Tesla.Adapter.TestCase, only: [https_url: 0]

      describe "SSL" do
        test "basic get request" do
          response = SSL.Client.get("#{https_url()}/ip")
          assert response.status == 200
        end
      end
    end
  end
end
