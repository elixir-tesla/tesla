defmodule Tesla.AdapterCase.SSL do
  defmacro __using__(opts) do
    quote do
      alias Tesla.Env

      describe "SSL" do
        test "GET request" do
          request = %Env{
            method: :get,
            url: "#{@https}/ip"
          }

          assert {:ok, %Env{} = response} = call(request, unquote(opts))
          assert response.status == 200
        end
      end
    end
  end
end
