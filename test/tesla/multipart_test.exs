defmodule Tesla.MultipartTest do
  use ExUnit.Case

  alias Tesla.Multipart

  test "headers" do
    mp = Multipart.new()

    headers = Multipart.headers(mp)

    assert headers == ["Content-Type": "multipart/form-data; boundary=#{mp.boundary}"]
  end

  test "add content-type param" do
    mp =
      Multipart.new()
      |> Multipart.add_content_type_param("charset=utf-8")

    headers = Multipart.headers(mp)

    assert headers == [
             "Content-Type": "multipart/form-data; boundary=#{mp.boundary}; charset=utf-8"
           ]
  end

  test "add content-type params" do
    mp =
      Multipart.new()
      |> Multipart.add_content_type_param("charset=utf-8")
      |> Multipart.add_content_type_param("foo=bar")

    headers = Multipart.headers(mp)

    assert headers == [
             "Content-Type":
               "multipart/form-data; boundary=#{mp.boundary}; charset=utf-8; foo=bar"
           ]
  end

  test "add_part (without headers)" do
    mp =
      Multipart.new()
      |> Multipart.add_part("some random content")

    body = Multipart.body(mp) |> Enum.join()

    assert body == "--#{mp.boundary}\r\n\r\nsome random content\r\n--#{mp.boundary}--"
  end

  test "add_part (with headers)" do
    mp =
      Multipart.new()
      |> Multipart.add_part("some random content", headers: ["Content-Type": "x-test-content"])

    body = Multipart.body(mp) |> Enum.join()

    assert body ==
             "--#{mp.boundary}\r\nContent-Type: x-test-content\r\n\r\nsome random content\r\n--#{
               mp.boundary
             }--"
  end

  test "add_field" do
    mp =
      Multipart.new()
      |> Multipart.add_field("foo", "bar")

    body = Multipart.body(mp) |> Enum.join()

    assert body ==
             "--#{mp.boundary}\r\nContent-Disposition: form-data; name=\"foo\"\r\n\r\nbar\r\n--#{
               mp.boundary
             }--"
  end

  test "add_field with extra headers" do
    mp =
      Multipart.new()
      |> Multipart.add_field(
        "foo",
        "bar",
        headers: [{:"Content-Id", 1}, {:"Content-Type", "text/plain"}]
      )

    body = Multipart.body(mp) |> Enum.join()

    assert body ==
             "--#{mp.boundary}\r\nContent-Id: 1\r\nContent-Type: text/plain\r\nContent-Disposition: form-data; name=\"foo\"\r\n\r\nbar\r\n--#{
               mp.boundary
             }--"
  end

  test "add_file (filename only)" do
    mp =
      Multipart.new()
      |> Multipart.add_file("test/tesla/multipart_test_file.sh")

    body = Multipart.body(mp) |> Enum.join()

    assert body ==
             "--#{mp.boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"multipart_test_file.sh\"\r\n\r\n#!/usr/bin/env bash\necho \"test multipart file\"\n\r\n--#{
               mp.boundary
             }--"
  end

  test "add_file (filename with name)" do
    mp =
      Multipart.new()
      |> Multipart.add_file("test/tesla/multipart_test_file.sh", name: "foobar")

    body = Multipart.body(mp) |> Enum.join()

    assert body ==
             "--#{mp.boundary}\r\nContent-Disposition: form-data; name=\"foobar\"; filename=\"multipart_test_file.sh\"\r\n\r\n#!/usr/bin/env bash\necho \"test multipart file\"\n\r\n--#{
               mp.boundary
             }--"
  end

  test "add_file (custom filename)" do
    mp =
      Multipart.new()
      |> Multipart.add_file("test/tesla/multipart_test_file.sh", filename: "custom.png")

    body = Multipart.body(mp) |> Enum.join()

    assert body ==
             "--#{mp.boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"custom.png\"\r\n\r\n#!/usr/bin/env bash\necho \"test multipart file\"\n\r\n--#{
               mp.boundary
             }--"
  end

  test "add_file (filename with name, extra headers)" do
    mp =
      Multipart.new()
      |> Multipart.add_file(
        "test/tesla/multipart_test_file.sh",
        name: "foobar",
        headers: [{:"Content-Id", 1}, {:"Content-Type", "text/plain"}]
      )

    body = Multipart.body(mp) |> Enum.join()

    assert body ==
             "--#{mp.boundary}\r\nContent-Id: 1\r\nContent-Type: text/plain\r\nContent-Disposition: form-data; name=\"foobar\"; filename=\"multipart_test_file.sh\"\r\n\r\n#!/usr/bin/env bash\necho \"test multipart file\"\n\r\n--#{
               mp.boundary
             }--"
  end

  test "add_file (detect content type)" do
    mp =
      Multipart.new()
      |> Multipart.add_file("test/tesla/multipart_test_file.sh", detect_content_type: true)

    body = Multipart.body(mp) |> Enum.join()

    assert body ==
             "--#{mp.boundary}\r\nContent-Type: application/x-sh\r\nContent-Disposition: form-data; name=\"file\"; filename=\"multipart_test_file.sh\"\r\n\r\n#!/usr/bin/env bash\necho \"test multipart file\"\n\r\n--#{
               mp.boundary
             }--"
  end

  test "add_file (detect content type overrides given header)" do
    mp =
      Multipart.new()
      |> Multipart.add_file(
        "test/tesla/multipart_test_file.sh",
        detect_content_type: true,
        headers: [{:"Content-Type", "foo/bar"}]
      )

    body = Multipart.body(mp) |> Enum.join()

    assert body ==
             "--#{mp.boundary}\r\nContent-Type: application/x-sh\r\nContent-Disposition: form-data; name=\"file\"; filename=\"multipart_test_file.sh\"\r\n\r\n#!/usr/bin/env bash\necho \"test multipart file\"\n\r\n--#{
               mp.boundary
             }--"
  end

  test "add_file_content" do
    mp =
      Multipart.new()
      |> Multipart.add_file_content("file-data", "data.gif")

    body = Multipart.body(mp) |> Enum.join()

    assert body ==
             "--#{mp.boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"data.gif\"\r\n\r\nfile-data\r\n--#{
               mp.boundary
             }--"
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
