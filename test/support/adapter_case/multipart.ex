defmodule Tesla.AdapterCase.Multipart do
  defmacro __using__(_) do
    quote do
      alias Tesla.Env
      alias Tesla.Multipart

      describe "Multipart" do
        test "POST request" do
          mp =
            Multipart.new()
            |> Multipart.add_content_type_param("charset=utf-8")
            |> Multipart.add_field("field1", "foo")
            |> Multipart.add_field(
              "field2",
              "bar",
              headers: [{:"Content-Id", 1}, {:"Content-Type", "text/plain"}]
            )
            |> Multipart.add_file("test/tesla/multipart_test_file.sh")
            |> Multipart.add_file("test/tesla/multipart_test_file.sh", name: "foobar")

          request = %Env{
            method: :post,
            url: "#{@http}/post",
            body: mp
          }

          assert {:ok, %Env{} = response} = call(request)
          assert response.status == 200
          assert Tesla.get_header(response, "content-type") == "application/json"

          assert {:ok, %Env{} = response} = Tesla.Middleware.JSON.decode(response, [])

          assert Regex.match?(
                   ~r[multipart/form-data; boundary=#{mp.boundary}; charset=utf-8$],
                   response.body["headers"]["content-type"]
                 )

          assert response.body["form"] == %{"field1" => "foo", "field2" => "bar"}

          assert response.body["files"] == %{
                   "file" => "#!/usr/bin/env bash\necho \"test multipart file\"\n",
                   "foobar" => "#!/usr/bin/env bash\necho \"test multipart file\"\n"
                 }
        end
      end
    end
  end
end
