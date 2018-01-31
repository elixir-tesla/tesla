defmodule Tesla.AdapterCase.SSL do
  defmacro __using__(_) do
    quote do
      alias Tesla.Env

      describe "SSL" do
        test "GET request" do
          request = %Env{
            method: :get,
            url: "https://github.com/teamon/tesla"
          }

          assert %Env{} = response = call(request)
          assert response.status == 200
        end
      end
    end
  end
end
