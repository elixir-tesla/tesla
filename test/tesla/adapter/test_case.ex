defmodule Tesla.Adapter.TestCase do
  @httpbin_url "http://localhost:#{Application.get_env(:httparrot, :http_port)}"

  def httpbin_url, do: @httpbin_url

  def text_plain_client do
    Tesla.build_client [
      {Tesla.Middleware.Headers, %{'Content-Type' => 'text/plain'}}
    ]
  end
end

defmodule Tesla.Adapter.TestCase.Basic do

  defmacro __using__([client: client]) do
    quote do
      import Tesla.Adapter.TestCase, only: [httpbin_url: 0, text_plain_client: 0]

      test "basic get request" do
        response = unquote(client).get(text_plain_client, "#{httpbin_url}/ip")
        assert response.status == 200
      end

      test "basic post request" do
        response = unquote(client).post(text_plain_client, "#{httpbin_url}/post", "some-post-data")
        assert response.status == 200
        assert Regex.match?(~r/some-post-data/, to_string(response.body))
      end
    end
  end
end

defmodule Tesla.Adapter.TestCase.StreamRequestBody do

  defmacro __using__([client: client]) do
    quote do
      import Tesla.Adapter.TestCase, only: [httpbin_url: 0, text_plain_client: 0]

      test "stream request body: Stream.map" do
        body = (1..5) |> Stream.map(&to_string/1)
        response = unquote(client).post(text_plain_client, "#{httpbin_url}/post", body)
        assert response.status == 200
        assert Regex.match?(~r/12345/, to_string(response.body))
      end

      test "stream request body: Stream.unfold" do
        body = Stream.unfold(5, fn 0 -> nil; n -> {n,n-1} end)
        |> Stream.map(&to_string/1)
        response = unquote(client).post(text_plain_client, "#{httpbin_url}/post", body)

        assert response.status == 200
        assert Regex.match?(~r/54321/, to_string(response.body))
      end
    end
  end
end
