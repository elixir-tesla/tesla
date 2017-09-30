defmodule Tesla.AdapterCase.StreamRequestBody do
  defmacro __using__([adapter: adapter]) do
    quote do
      defmodule S.Client do
        use Tesla

        adapter unquote(adapter)
      end

      import Tesla.AdapterCase, only: [http_url: 0]

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
