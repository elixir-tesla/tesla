defmodule Tesla.AdapterCase.Basic do
  defmacro __using__(opts \\ []) do
    quote do
      alias Tesla.AdapterCase.Echo
      alias Tesla.Env

      @connection_refused_reason Keyword.get(
                                   unquote(opts),
                                   :connection_refused_reason,
                                   :econnrefused
                                 )
      @empty_response_body Keyword.get(unquote(opts), :empty_response_body, "")

      describe "Basic" do
        test "HEAD request" do
          request = %Env{
            method: :head,
            url: "#{@http}/ip"
          }

          assert {:ok, %Env{} = response} = call(request)
          assert response.status == 200
          assert response.body == @empty_response_body
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
          assert Echo.request_body(response.body) == "some-post-data"
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
          assert Echo.request_body(response.body) == "1 \u00F8 2 \u0111 1 \u00F8 2 \u0111"
        end

        test "POST request with control bytes" do
          body = for byte <- 0..127, into: "", do: <<byte>>

          request = %Env{
            method: :post,
            url: "#{@http}/post",
            body: body,
            headers: [{"content-type", "application/octet-stream"}]
          }

          assert {:ok, %Env{} = response} = call(request)
          assert response.status == 200
          assert Echo.request_body(response.body) == body
          assert Echo.request_header(response.body, "content-length") == "128"
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

        test "encoding query params with www_form by default" do
          request = %Env{
            method: :get,
            url: "#{@http}/get",
            query: [user_name: "John Smith"]
          }

          assert {:ok, %Env{} = response} = call(request)
          assert {:ok, %Env{} = response} = Tesla.Middleware.JSON.decode(response, [])

          assert response.body["url"] == "#{@http}/get?user_name=John+Smith"
        end

        test "encoding query params with rfc3986 optionally" do
          request = %Env{
            method: :get,
            url: "#{@http}/get",
            query: [user_name: "John Smith"],
            opts: [query_encoding: :rfc3986]
          }

          assert {:ok, %Env{} = response} = call(request)
          assert {:ok, %Env{} = response} = Tesla.Middleware.JSON.decode(response, [])

          assert response.body["url"] == "#{@http}/get?user_name=John%20Smith"
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

          assert {:error, reason} = call(request)
          assert unwrap_reason(reason) == @connection_refused_reason
        end
      end

      defp unwrap_reason(%{reason: reason}), do: unwrap_reason(reason)
      defp unwrap_reason({:error, reason}), do: unwrap_reason(reason)
      defp unwrap_reason(reason), do: reason
    end
  end
end
