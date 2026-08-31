defmodule Tesla.AdapterCase.StreamRequestBody do
  defmacro __using__(_) do
    quote do
      alias Tesla.Env

      describe "Stream Request" do
        test "stream request body: Stream.map" do
          assert_streamed_body_arrives_intact(Stream.map(1..5, &to_string/1))
        end

        test "stream request body: Stream.unfold" do
          body =
            Stream.unfold(5, fn
              0 -> nil
              n -> {n, n - 1}
            end)
            |> Stream.map(&to_string/1)

          assert_streamed_body_arrives_intact(body)
        end

        test "stream request body: Stream.take" do
          assert_streamed_body_arrives_intact(1..9 |> Stream.map(&to_string/1) |> Stream.take(5))
        end

        test "stream request body: Stream.take of the whole stream" do
          assert_streamed_body_arrives_intact(1..5 |> Stream.map(&to_string/1) |> Stream.take(5))
        end

        test "stream request body: Stream.take of nothing" do
          assert_streamed_body_arrives_intact(1..9 |> Stream.map(&to_string/1) |> Stream.take(0))
        end

        test "stream request body: Stream.take_while that matches nothing" do
          body = 1..9 |> Stream.map(&to_string/1) |> Stream.take_while(fn _ -> false end)

          assert_streamed_body_arrives_intact(body)
        end
      end

      defp assert_streamed_body_arrives_intact(body) do
        request = %Env{
          method: :post,
          url: "#{@http}/post",
          headers: [{"content-type", "text/plain"}],
          body: body
        }

        assert {:ok, %Env{} = response} = call(request)
        assert response.status == 200
        assert echoed_request_body(response.body) == Enum.join(body)
      end

      defp echoed_request_body(response_body) do
        response_body
        |> to_string()
        |> Jason.decode!()
        |> Map.fetch!("data")
      end
    end
  end
end
