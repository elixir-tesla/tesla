defmodule Tesla.AdapterCase.Query do
  defmacro __using__(_) do
    quote do
      alias Tesla.Env

      describe "QUERY (RFC 10008)" do
        # The test server does not implement the QUERY method and rejects it
        # (currently with 501, but that may vary with the server version).
        # Receiving an HTTP response (instead of an error) is what proves the
        # adapter can send QUERY requests over the wire.
        test "QUERY request" do
          request = %Env{
            method: :query,
            url: "#{@http}/post",
            body: "select=surname,givenname&limit=10",
            headers: [{"content-type", "application/x-www-form-urlencoded"}]
          }

          assert {:ok, %Env{} = response} = call(request)
          assert response.status in 100..599
        end
      end
    end
  end
end
