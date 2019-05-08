defmodule Tesla.AdapterCase.StreamRequestBody do
  defmacro __using__(_) do
    quote do
      alias Tesla.Env

      describe "Stream" do
        test "stream request body: Stream.map" do
          request = %Env{
            method: :post,
            url: "#{@http}/post",
            headers: [{"content-type", "text/plain"}],
            body: Stream.map(1..5, &to_string/1)
          }

          assert {:ok, %Env{} = response} = call(request)
          assert response.status == 200
          assert Regex.match?(~r/12345/, to_string(response.body))
        end

        test "stream request body: Stream.unfold" do
          body =
            Stream.unfold(5, fn
              0 -> nil
              n -> {n, n - 1}
            end)
            |> Stream.map(&to_string/1)

          request = %Env{
            method: :post,
            url: "#{@http}/post",
            headers: [{"content-type", "text/plain"}],
            body: body
          }

          assert {:ok, %Env{} = response} = call(request)
          assert response.status == 200
          assert Regex.match?(~r/54321/, to_string(response.body))
        end
      end
    end
  end
end
