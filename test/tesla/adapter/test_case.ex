defmodule Tesla.Adapter.TestCase.Basic do
  defmacro __using__([client: client]) do
    quote do
      test "basic get request" do
        response = unquote(client).get("http://httpbin.org/ip")
        assert response.status == 200
      end

      test "basic post request" do
        response = unquote(client).post("http://httpbin.org/post", "some-post-data")
        assert response.status == 200
        assert Regex.match?(~r/some-post-data/, to_string(response.body))
      end
    end
  end
end

defmodule Tesla.Adapter.TestCase.StreamRequestBody do
  defmacro __using__([client: client]) do
    quote do
      test "stream request body: Stream.map" do
        body = (1..5) |> Stream.map(&to_string/1)
        response = unquote(client).post("http://httpbin.org/post", body)
        assert response.status == 200
        assert Regex.match?(~r/12345/, to_string(response.body))
      end

      test "stream request body: Stream.unfold" do
        body = Stream.unfold(5, fn 0 -> nil; n -> {n,n-1} end)
        |> Stream.map(&to_string/1)
        response = unquote(client).post("http://httpbin.org/post", body)

        assert response.status == 200
        assert Regex.match?(~r/54321/, to_string(response.body))
      end
    end
  end
end
