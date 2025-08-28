defmodule Tesla.MultipartTest do
  use ExUnit.Case

  alias Tesla.Multipart

  test "headers" do
    mp = Multipart.new()

    headers = Multipart.headers(mp)

    assert headers == [{"content-type", "multipart/form-data; boundary=#{mp.boundary}"}]
  end

  test "add content-type param" do
    mp =
      Multipart.new()
      |> Multipart.add_content_type_param("charset=utf-8")

    headers = Multipart.headers(mp)

    assert headers == [
             {"content-type", "multipart/form-data; boundary=#{mp.boundary}; charset=utf-8"}
           ]
  end

  test "add content-type params" do
    mp =
      Multipart.new()
      |> Multipart.add_content_type_param("charset=utf-8")
      |> Multipart.add_content_type_param("foo=bar")

    headers = Multipart.headers(mp)

    assert headers == [
             {"content-type",
              "multipart/form-data; boundary=#{mp.boundary}; charset=utf-8; foo=bar"}
           ]
  end

  test "add_field" do
    mp =
      Multipart.new()
      |> Multipart.add_field("foo", "bar")

    body = Multipart.body(mp) |> Enum.join()

    assert body == """
           --#{mp.boundary}\r
           content-disposition: form-data; name="foo"\r
           \r
           bar\r
           --#{mp.boundary}--\r
           """
  end

  test "add_field with extra headers" do
    mp =
      Multipart.new()
      |> Multipart.add_field(
        "foo",
        "bar",
        headers: [{"content-id", "1"}, {"content-type", "text/plain"}]
      )

    body = Multipart.body(mp) |> Enum.join()

    assert body == """
           --#{mp.boundary}\r
           content-id: 1\r
           content-type: text/plain\r
           content-disposition: form-data; name="foo"\r
           \r
           bar\r
           --#{mp.boundary}--\r
           """
  end

  test "add_file (filename only)" do
    mp =
      Multipart.new()
      |> Multipart.add_file("test/tesla/multipart_test_file.sh")

    body = Multipart.body(mp) |> Enum.join()

    assert body == """
           --#{mp.boundary}\r
           content-disposition: form-data; name="file"; filename="multipart_test_file.sh"\r
           \r
           #!/usr/bin/env bash
           echo "test multipart file"
           \r
           --#{mp.boundary}--\r
           """
  end

  test "add_file (filename with name)" do
    mp =
      Multipart.new()
      |> Multipart.add_file("test/tesla/multipart_test_file.sh", name: "foobar")

    body = Multipart.body(mp) |> Enum.join()

    assert body == """
           --#{mp.boundary}\r
           content-disposition: form-data; name="foobar"; filename="multipart_test_file.sh"\r
           \r
           #!/usr/bin/env bash
           echo "test multipart file"
           \r
           --#{mp.boundary}--\r
           """
  end

  test "add_file (custom filename)" do
    mp =
      Multipart.new()
      |> Multipart.add_file("test/tesla/multipart_test_file.sh", filename: "custom.png")

    body = Multipart.body(mp) |> Enum.join()

    assert body == """
           --#{mp.boundary}\r
           content-disposition: form-data; name="file"; filename="custom.png"\r
           \r
           #!/usr/bin/env bash
           echo "test multipart file"
           \r
           --#{mp.boundary}--\r
           """
  end

  test "add_file (filename with name, extra headers)" do
    mp =
      Multipart.new()
      |> Multipart.add_file(
        "test/tesla/multipart_test_file.sh",
        name: "foobar",
        headers: [{"content-id", "1"}, {"content-type", "text/plain"}]
      )

    body = Multipart.body(mp) |> Enum.join()

    assert body == """
           --#{mp.boundary}\r
           content-id: 1\r
           content-type: text/plain\r
           content-disposition: form-data; name="foobar"; filename="multipart_test_file.sh"\r
           \r
           #!/usr/bin/env bash
           echo "test multipart file"
           \r
           --#{mp.boundary}--\r
           """
  end

  test "add_file (detect content type)" do
    mp =
      Multipart.new()
      |> Multipart.add_file("test/tesla/multipart_test_file.sh", detect_content_type: true)

    body = Multipart.body(mp) |> Enum.join()

    assert body == """
           --#{mp.boundary}\r
           content-type: application/x-sh\r
           content-disposition: form-data; name="file"; filename="multipart_test_file.sh"\r
           \r
           #!/usr/bin/env bash
           echo "test multipart file"
           \r
           --#{mp.boundary}--\r
           """
  end

  test "add_file (detect content type overrides given header)" do
    mp =
      Multipart.new()
      |> Multipart.add_file(
        "test/tesla/multipart_test_file.sh",
        detect_content_type: true,
        headers: [{"content-type", "foo/bar"}]
      )

    body = Multipart.body(mp) |> Enum.join()

    assert body == """
           --#{mp.boundary}\r
           content-type: application/x-sh\r
           content-disposition: form-data; name="file"; filename="multipart_test_file.sh"\r
           \r
           #!/usr/bin/env bash
           echo "test multipart file"
           \r
           --#{mp.boundary}--\r
           """
  end

  test "add_file_content" do
    mp =
      Multipart.new()
      |> Multipart.add_file_content("file-data", "data.gif")

    body = Multipart.body(mp) |> Enum.join()

    assert body == """
           --#{mp.boundary}\r
           content-disposition: form-data; name="file"; filename="data.gif"\r
           \r
           file-data\r
           --#{mp.boundary}--\r
           """
  end

  test "add non-existing file" do
    mp =
      Multipart.new()
      |> Multipart.add_file("i-do-not-exists.txt")

    assert_raise File.Error, fn ->
      mp |> Multipart.body() |> Enum.to_list()
    end
  end

  describe "add_field" do
    test "numbers raise argument error" do
      assert_raise ArgumentError, fn ->
        Multipart.new()
        |> Multipart.add_field("foo", 123)
      end

      assert_raise ArgumentError, fn ->
        Multipart.new()
        |> Multipart.add_field("bar", 123.00)
      end
    end

    test "maps raise argument error" do
      assert_raise ArgumentError, fn ->
        Multipart.new()
        |> Multipart.add_field("foo", %{hello: :world})
      end
    end

    test "Iodata" do
      mp =
        Multipart.new()
        |> Multipart.add_field("foo", ["bar", "baz"])

      body = Multipart.body(mp) |> Enum.join()

      assert body == """
             --#{mp.boundary}\r
             content-disposition: form-data; name="foo"\r
             \r
             barbaz\r
             --#{mp.boundary}--\r
             """
    end

    test "IO.Stream" do
      mp =
        Multipart.new()
        |> Multipart.add_field("foo", %IO.Stream{})

      assert is_function(Multipart.body(mp))
    end

    test "File.Stream" do
      mp =
        Multipart.new()
        |> Multipart.add_field("foo", %File.Stream{})

      assert is_function(Multipart.body(mp))

      stream = File.stream!("test/tesla/multipart_test_file.sh")

      mp2 =
        Multipart.new()
        |> Multipart.add_field("bar", stream)

      assert is_function(Multipart.body(mp2))
    end

    test "normal stream" do
      stream = Stream.map([1, 2, 3], fn x -> to_string(x) end)

      mp =
        Multipart.new()
        |> Multipart.add_field("foo", stream)

      assert is_function(Multipart.body(mp))
    end

    test "function/2 streaming response" do
      stream_fun =
        Stream.resource(
          fn -> ["chunk1", "chunk2", "final"] end,
          fn
            [head | tail] -> {[head], tail}
            [] -> {:halt, []}
          end,
          fn _ -> :ok end
        )

      mp =
        Multipart.new()
        |> Multipart.add_field("stream_field", stream_fun)

      assert is_function(Multipart.body(mp))
    end

    test "function/2 streaming response with file content" do
      stream_fun =
        Stream.resource(
          fn -> ["file data chunk 1", "file data chunk 2"] end,
          fn
            [head | tail] -> {[head], tail}
            [] -> {:halt, []}
          end,
          fn _ -> :ok end
        )

      mp =
        Multipart.new()
        |> Multipart.add_file_content(stream_fun, "streamed_file.mp4")
        |> Multipart.add_field("model", "whisper-1")
        |> Multipart.add_field("response_format", "json")

      assert is_function(Multipart.body(mp))

      body_stream = Multipart.body(mp)
      body_content = body_stream |> Enum.to_list() |> IO.iodata_to_binary()

      assert body_content =~ ~s(name="file"; filename="streamed_file.mp4")
      assert body_content =~ "file data chunk 1"
      assert body_content =~ "file data chunk 2"
      assert body_content =~ ~s(name="model")
      assert body_content =~ "whisper-1"
      assert body_content =~ ~s(name="response_format")
      assert body_content =~ "json"
    end

    test "raw function/2 like Tesla adapter returns" do
      stream_fun = fn
        {:cont, acc} -> {:suspended, "data", acc}
        {:halt, acc} -> {:halted, acc}
      end

      mp =
        Multipart.new()
        |> Multipart.add_file_content(stream_fun, "test.mp4")

      assert %Multipart{} = mp
      assert length(mp.parts) == 1
    end
  end

  describe "streaming function support" do
    @http "http://localhost:#{Application.compile_env(:httparrot, :http_port)}"

    defp call_adapter(adapter, env, opts \\ []) do
      case adapter do
        {adapter_module, adapter_opts} ->
          adapter_module.call(env, Keyword.merge(opts, adapter_opts))

        adapter_module ->
          adapter_module.call(env, opts)
      end
    end

    test "accepts Stream.resource functions from Tesla adapters" do
      stream_data =
        Stream.resource(
          fn -> ["chunk1", "chunk2", "chunk3"] end,
          fn
            [head | tail] -> {[head], tail}
            [] -> {:halt, []}
          end,
          fn _ -> :ok end
        )

      mp =
        Multipart.new()
        |> Multipart.add_file_content(stream_data, "streamed_file.txt")
        |> Multipart.add_field("type", "stream_test")

      request = %Tesla.Env{
        method: :post,
        url: "#{@http}/post",
        body: mp
      }

      assert {:ok, response} = call_adapter(Tesla.Adapter.Mint, request)
      assert response.status == 200

      {:ok, response} = Tesla.Middleware.JSON.decode(response, [])

      assert response.body["form"]["type"] == "stream_test"
      assert response.body["files"]["file"] == "chunk1chunk2chunk3"

      content_type = response.body["headers"]["content-type"]
      assert content_type =~ "multipart/form-data"
      assert content_type =~ "boundary="
    end

    test "works with File.Stream across different adapters" do
      file_stream = File.stream!("test/tesla/multipart_test_file.sh")

      mp =
        Multipart.new()
        |> Multipart.add_file_content(file_stream, "test_script.sh")
        |> Multipart.add_field("adapter", "hackney")

      request = %Tesla.Env{
        method: :post,
        url: "#{@http}/post",
        body: mp
      }

      assert {:ok, response} = call_adapter(Tesla.Adapter.Hackney, request)
      assert response.status == 200

      {:ok, response} = Tesla.Middleware.JSON.decode(response, [])

      assert response.body["form"]["adapter"] == "hackney"

      assert response.body["files"]["file"] ==
               "#!/usr/bin/env bash\necho \"test multipart file\"\n"
    end

    test "reproduces GitHub issue #648 scenario" do
      gcp_stream_response =
        Stream.resource(
          fn -> ["audio_data_chunk_1", "audio_data_chunk_2", "audio_data_chunk_3"] end,
          fn
            [head | tail] -> {[head], tail}
            [] -> {:halt, []}
          end,
          fn _ -> :ok end
        )

      upload_body =
        Multipart.new()
        |> Multipart.add_file_content(gcp_stream_response, "audio.mp4")
        |> Multipart.add_field("model", "whisper-1")
        |> Multipart.add_field("response_format", "json")

      request = %Tesla.Env{
        method: :post,
        url: "#{@http}/post",
        body: upload_body
      }

      assert {:ok, response} = call_adapter(Tesla.Adapter.Mint, request)
      assert response.status == 200

      {:ok, response} = Tesla.Middleware.JSON.decode(response, [])

      assert response.body["form"]["model"] == "whisper-1"
      assert response.body["form"]["response_format"] == "json"

      assert response.body["files"]["file"] ==
               "audio_data_chunk_1audio_data_chunk_2audio_data_chunk_3"
    end

    test "handles large streaming data efficiently" do
      large_stream = Stream.repeatedly(fn -> "data_chunk_" end) |> Stream.take(100)

      mp =
        Multipart.new()
        |> Multipart.add_file_content(large_stream, "large_file.dat")
        |> Multipart.add_field("size", "large")

      request = %Tesla.Env{
        method: :post,
        url: "#{@http}/post",
        body: mp
      }

      assert {:ok, response} = call_adapter(Tesla.Adapter.Mint, request)
      assert response.status == 200

      {:ok, response} = Tesla.Middleware.JSON.decode(response, [])

      assert response.body["form"]["size"] == "large"

      file_content = response.body["files"]["file"]
      assert String.contains?(file_content, "data_chunk_")

      expected_length = String.length("data_chunk_") * 100
      actual_length = String.length(file_content)
      assert abs(actual_length - expected_length) < 50
    end
  end
end
