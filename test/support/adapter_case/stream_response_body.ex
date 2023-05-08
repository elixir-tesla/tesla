defmodule Tesla.AdapterCase.StreamResponseBody do
  defmacro __using__(_) do
    quote do
      alias Tesla.Env

      describe "Stream Response" do
        test "stream response body" do
          request = %Env{
            method: :get,
            url: "#{@http}/stream/20"
          }

          assert {:ok, %Env{} = response} = call(request, response: :stream)
          assert response.status == 200
          assert is_function(response.body) || response.body.__struct__ == Stream

          body = Enum.to_list(response.body)
          assert Enum.count(body) == 20
        end
      end
    end
  end
end
