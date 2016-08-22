defmodule Tesla.Adapter.TestCase do

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
