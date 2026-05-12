defmodule Tesla.PathParamTest do
  use ExUnit.Case, async: true

  alias Tesla.Env
  alias Tesla.PathParam
  alias Tesla.PathParams

  @middleware Tesla.Middleware.PathParams

  test "uses default serialization options" do
    assert %PathParam{
             name: "id",
             style: :simple,
             explode: false,
             allow_reserved: false
           } = PathParam.new!("id")
  end

  test "accepts explicit serialization options" do
    assert %PathParam{
             name: "id",
             style: :label,
             explode: true,
             allow_reserved: true
           } =
             PathParam.new!("id",
               style: :label,
               explode: true,
               allow_reserved: true
             )
  end

  test "inspects static metadata" do
    inspected = inspect(PathParam.new!("token", style: :matrix))

    assert inspected =~ ~s(name: "token")
    assert inspected =~ "style: :matrix"
  end

  test "serializes a path parameter with explicit keyword options" do
    path_params = PathParams.new!([PathParam.new!("coords", style: :matrix, explode: true)])
    opts = [path_params: %{"coords" => ["blue", "black"]}]

    assert {:ok, env} =
             @middleware.call(
               %Env{
                 url: "/items/{coords}",
                 opts: opts,
                 private: PathParams.put_private(path_params)
               },
               [],
               mode: :modern
             )

    assert env.url == "/items/;coords=blue;coords=black"
  end

  test "rejects document location as a hand-written option" do
    assert_raise ArgumentError, ~r/unknown keys \[:in\]/, fn ->
      PathParam.new!("color", in: :path)
    end
  end

  test "rejects string styles in hand-written keyword options" do
    assert_raise ArgumentError, ~r/expected :simple, :matrix, or :label/, fn ->
      PathParam.new!("color", style: "matrix")
    end
  end

  test "rejects non-path style atoms" do
    for style <- [:form, :space_delimited, :pipe_delimited, :deep_object, :cookie] do
      assert_raise ArgumentError, ~r/expected :simple, :matrix, or :label/, fn ->
        PathParam.new!("color", style: style)
      end
    end
  end

  test "rejects non-string names" do
    assert_raise ArgumentError, ~r/expected path parameter name to be a string/, fn ->
      PathParam.new!(:color)
    end
  end

  test "rejects non-boolean explode option" do
    assert_raise ArgumentError, ~r/expected :explode to be a boolean/, fn ->
      PathParam.new!("color", explode: "true")
    end
  end

  test "rejects non-boolean allow_reserved option" do
    assert_raise ArgumentError, ~r/expected :allow_reserved to be a boolean/, fn ->
      PathParam.new!("color", allow_reserved: 1)
    end
  end

  test "rejects atom-keyed maps as options" do
    assert_raise ArgumentError, ~r/expected path parameter options to be a keyword list/, fn ->
      PathParam.new!("color", %{style: :matrix})
    end
  end

  test "rejects string-keyed maps as options" do
    assert_raise ArgumentError, ~r/expected path parameter options to be a keyword list/, fn ->
      PathParam.new!("color", %{"style" => :matrix})
    end
  end

  test "rejects non-keyword lists as options" do
    assert_raise ArgumentError, ~r/expected a keyword list/, fn ->
      PathParam.new!("color", [:matrix])
    end
  end

  test "encodes values with the unreserved set by default" do
    param = PathParam.new!("id")

    assert PathParam.encode_value(param, "AZaz09-_.~") == "AZaz09-_.~"
    assert PathParam.encode_value(param, "a b/c?d#é%") == "a%20b%2Fc%3Fd%23%C3%A9%25"
  end

  test "encodes values while preserving allowed reserved path characters" do
    param = PathParam.new!("id", allow_reserved: true)

    assert PathParam.encode_value(param, "!$&'()*+,;=:@") == "!$&'()*+,;=:@"
    assert PathParam.encode_value(param, "/?#[] é") == "%2F%3F%23%5B%5D%20%C3%A9"
    assert PathParam.encode_value(param, "") == ""
  end

  test "preserves valid percent triplets and escapes invalid ones when reserved are allowed" do
    param = PathParam.new!("id", allow_reserved: true)

    assert PathParam.encode_value(param, "%20%2F%AF%af") == "%20%2F%AF%af"
    assert PathParam.encode_value(param, "%2G%zz%") == "%252G%25zz%25"
  end
end
