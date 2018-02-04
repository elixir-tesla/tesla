defmodule Tesla.AdapterCase.Basic do
  defmacro __using__(_) do
    quote do
      alias Tesla.Env

      describe "Basic" do
        test "HEAD request" do
          request = %Env{
            method: :head,
            url: "#{@http}/ip"
          }

          assert {:ok, %Env{} = response} = call(request)
          assert response.status == 200
        end

        test "GET request" do
          request = %Env{
            method: :get,
            url: "#{@http}/ip"
          }

          assert {:ok, %Env{} = response} = call(request)
          assert response.status == 200
        end

        test "POST request" do
          request = %Env{
            method: :post,
            url: "#{@http}/post",
            body: "some-post-data",
            headers: [{"content-type", "text/plain"}]
          }

          assert {:ok, %Env{} = response} = call(request)
          assert response.status == 200
          assert Tesla.get_header(response, "content-type") == "application/json"
          assert Regex.match?(~r/some-post-data/, response.body)
        end

        test "unicode" do
          request = %Env{
            method: :post,
            url: "#{@http}/post",
            body: "1 ø 2 đ 1 \u00F8 2 \u0111",
            headers: [{"content-type", "text/plain"}]
          }

          assert {:ok, %Env{} = response} = call(request)
          assert response.status == 200
          assert Tesla.get_header(response, "content-type") == "application/json"
          assert Regex.match?(~r/1 ø 2 đ 1 ø 2 đ/, response.body)
        end

        test "passing query params" do
          request = %Env{
            method: :get,
            url: "#{@http}/get",
            query: [
              page: 1,
              sort: "desc",
              status: ["a", "b", "c"],
              user: [name: "Jon", age: 20]
            ]
          }

          assert {:ok, %Env{} = response} = call(request)
          assert response.status == 200

          assert {:ok, %Env{} = response} = Tesla.Middleware.JSON.decode(response, [])

          args = response.body["args"]

          assert args["page"] == "1"
          assert args["sort"] == "desc"
          assert args["status[]"] == ["a", "b", "c"]
          assert args["user[name]"] == "Jon"
          assert args["user[age]"] == "20"
        end

        test "autoredirects disabled by default" do
          request = %Env{
            method: :get,
            url: "#{@http}/redirect-to?url=#{@http}/status/200"
          }

          assert {:ok, %Env{} = response} = call(request)
          assert response.status == 301
        end

        test "error: connection refused" do
          request = %Env{
            method: :get,
            url: "http://localhost:1234"
          }

          assert {:error, _} = call(request)
        end
      end
    end
  end
end
