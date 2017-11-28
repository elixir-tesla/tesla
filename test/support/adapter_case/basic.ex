defmodule Tesla.AdapterCase.Basic do
  defmacro __using__(_) do
    quote do
      alias Tesla.Env

      describe "Basic" do
        test "HEAD request" do
          request = %Env{
            method: :head,
            url: "#{@url}/ip"
          }

          assert %Env{} = response = call(request)
          assert response.status == 200
        end

        test "GET request" do
          request = %Env{
            method: :get,
            url: "#{@url}/ip"
          }

          assert %Env{} = response = call(request)
          assert response.status == 200
        end

        test "POST request" do
          request = %Env{
            method: :post,
            url: "#{@url}/post",
            body: "some-post-data",
            headers: %{"Content-Type" => "text/plain"}
          }

          assert %Env{} = response = call(request)
          assert response.status == 200
          assert response.headers["content-type"] == "application/json"
          assert Regex.match?(~r/some-post-data/, response.body)
        end

        test "unicode" do
          request = %Env{
            method: :post,
            url: "#{@url}/post",
            body: "1 ø 2 đ 1 \u00F8 2 \u0111",
            headers: %{"Content-Type" => "text/plain"}
          }

          assert %Env{} = response = call(request)
          assert response.status == 200
          assert response.headers["content-type"] == "application/json"
          assert Regex.match?(~r/1 ø 2 đ 1 ø 2 đ/, response.body)
        end

        test "passing query params" do
          request = %Env{
            method: :get,
            url: "#{@url}/get",
            query: [
              page: 1, sort: "desc",
              status: ["a", "b", "c"],
              user: [name: "Jon", age: 20]
            ]
          }

          assert %Env{} = response = call(request)
          assert response.status == 200

          response = Tesla.Middleware.JSON.decode(response, [])

          args = response.body["args"]

          assert args["page"] == "1"
          assert args["sort"] == "desc"
          assert args["status[]"]   == ["a", "b", "c"]
          assert args["user[name]"] == "Jon"
          assert args["user[age]"]  == "20"
        end

        test "capturing GET query params from url/path when there is nothing to capture" do
          request = %Env{
            method: :get,
            url: "#{@url}/get"
          }

          assert %Env{} = response = call(request)

          response = Tesla.Middleware.JSON.decode(response, [])

          query = response.query

          assert query == []
        end

        test "capturing GET query params from url/path" do
          request = %Env{
            method: :get,
            url: "#{@url}/get?page=1&sort=desc&status[]=a&status[]=b&status[]=c&user[name]=Jon&user[age]=20"
          }

          assert %Env{} = response = call(request)

          response = Tesla.Middleware.JSON.decode(response, [])

          query = response.query

          assert query["page"] == "1"
          assert query["sort"] == "desc"
          assert query["status[]"]   == ["a", "b", "c"]
          assert query["user[name]"] == "Jon"
          assert query["user[age]"]  == "20"
        end

        test "autoredirects disabled by default" do
          request = %Env{
            method: :get,
            url: "#{@url}/redirect-to?url=#{@url}/status/200",
          }

          assert %Env{} = response = call(request)
          assert response.status == 301
        end

        test "error: connection refused" do
          request = %Env{
            method: :get,
            url: "http://localhost:1234",
          }

          assert_raise Tesla.Error, fn ->
            call(request)
          end
        end
      end
    end
  end
end
