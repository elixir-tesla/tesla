defmodule Tesla.MultipartTest do
  use ExUnit.Case

  alias Tesla.Multipart

  test "headers" do
    mp =
      Multipart.new

    headers = Multipart.headers(mp)

    assert headers == ["Content-Type": "multipart/form-data; boundary=#{mp.boundary}"]
  end

  test "add content-type param" do
    mp =
      Multipart.new
      |> Multipart.add_content_type_param("charset=utf-8")

    headers = Multipart.headers(mp)

    assert headers == ["Content-Type": "multipart/form-data; boundary=#{mp.boundary}; charset=utf-8"]
  end

  test "add content-type params" do
    mp =
      Multipart.new
      |> Multipart.add_content_type_param("charset=utf-8")
      |> Multipart.add_content_type_param("foo=bar")

    headers = Multipart.headers(mp)

    assert headers == ["Content-Type": "multipart/form-data; boundary=#{mp.boundary}; charset=utf-8; foo=bar"]
  end

  test "add_field" do
    mp =
      Multipart.new
      |> Multipart.add_field("foo", "bar")

    body = Multipart.body(mp) |> Enum.join

    assert body == """
--#{mp.boundary}\r
Content-Disposition: form-data; name="foo"\r
\r
bar\r
--#{mp.boundary}--\r
"""
  end

  test "add_field with extra headers" do
    mp =
      Multipart.new
      |> Multipart.add_field("foo", "bar", headers: [{:"Content-Id", 1}, {:"Content-Type", "text/plain"}])

    body = Multipart.body(mp) |> Enum.join

    assert body == """
--#{mp.boundary}\r
Content-Id: 1\r
Content-Type: text/plain\r
Content-Disposition: form-data; name="foo"\r
\r
bar\r
--#{mp.boundary}--\r
"""
  end

  test "add_file (filename only)" do
    mp =
      Multipart.new
      |> Multipart.add_file("test/tesla/multipart_test_file.sh")

    body = Multipart.body(mp) |> Enum.join

    assert body == """
--#{mp.boundary}\r
Content-Disposition: form-data; name="file"; filename="multipart_test_file.sh"\r
\r
#!/usr/bin/env bash
echo "test multipart file"
\r
--#{mp.boundary}--\r
"""
  end

  test "add_file (filename with name)" do
    mp =
      Multipart.new
      |> Multipart.add_file("test/tesla/multipart_test_file.sh", name: "foobar")

    body = Multipart.body(mp) |> Enum.join

    assert body == """
--#{mp.boundary}\r
Content-Disposition: form-data; name="foobar"; filename="multipart_test_file.sh"\r
\r
#!/usr/bin/env bash
echo "test multipart file"
\r
--#{mp.boundary}--\r
"""
  end

  test "add_file (filename with name, extra headers)" do
    mp =
      Multipart.new
      |> Multipart.add_file("test/tesla/multipart_test_file.sh", name: "foobar", headers: [{:"Content-Id", 1}, {:"Content-Type", "text/plain"}])
    body = Multipart.body(mp) |> Enum.join

    assert body == """
--#{mp.boundary}\r
Content-Id: 1\r
Content-Type: text/plain\r
Content-Disposition: form-data; name="foobar"; filename="multipart_test_file.sh"\r
\r
#!/usr/bin/env bash
echo "test multipart file"
\r
--#{mp.boundary}--\r
"""
  end

  test "add_file (detect content type)" do
    mp =
      Multipart.new
      |> Multipart.add_file("test/tesla/multipart_test_file.sh", detect_content_type: true)

    body = Multipart.body(mp) |> Enum.join

    assert body == """
--#{mp.boundary}\r
Content-Type: application/x-sh\r
Content-Disposition: form-data; name="file"; filename="multipart_test_file.sh"\r
\r
#!/usr/bin/env bash
echo "test multipart file"
\r
--#{mp.boundary}--\r
"""
  end

  test "add_file (detect content type overrides given header)" do
    mp =
      Multipart.new
      |> Multipart.add_file("test/tesla/multipart_test_file.sh", detect_content_type: true, headers: [{:"Content-Type", "foo/bar"}])

    body = Multipart.body(mp) |> Enum.join

    assert body == """
--#{mp.boundary}\r
Content-Type: application/x-sh\r
Content-Disposition: form-data; name="file"; filename="multipart_test_file.sh"\r
\r
#!/usr/bin/env bash
echo "test multipart file"
\r
--#{mp.boundary}--\r
"""
  end

  test "add_file (file doesn't exist)" do
    mp =
      Multipart.new
      |> Multipart.add_file("test/tesla/invalid")

    refute mp.valid
  end

  test "add_file! (file exist)" do
    assert Multipart.new |> Multipart.add_file!("test/tesla/multipart_test_file.sh")
  end

  test "add_file! (file doesn't exist)" do
    assert_raise Tesla.Error, "file test/tesla/invalid doesn't exist", fn ->
      Multipart.new
      |> Multipart.add_file!("test/tesla/invalid")
    end
  end
end
