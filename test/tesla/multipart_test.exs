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

  test "add_field with invalid arguments raises error" do
    assert_raise ArgumentError, fn ->
      Multipart.new()
      |> Multipart.add_field("foo", 123)
    end
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
end
