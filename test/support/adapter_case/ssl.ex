defmodule Tesla.AdapterCase.SSL do
  defmacro __using__([adapter: adapter]) do
    quote do
      defmodule SSL.Client do
        use Tesla

        adapter unquote(adapter)
      end

      import Tesla.AdapterCase, only: [https_url: 0]

      describe "SSL" do
        test "basic get request" do
          response = SSL.Client.get("#{https_url()}/ip")
          assert response.status == 200
        end
      end
    end
  end
end
