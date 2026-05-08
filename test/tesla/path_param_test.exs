defmodule Tesla.PathParamTest do
  use ExUnit.Case, async: true

  alias Tesla.Env
  alias Tesla.PathParam

  @middleware Tesla.Middleware.PathParams

  test "uses default serialization options" do
    assert %PathParam{
             name: "id",
             value: 42,
             style: :simple,
             explode: false,
             allow_reserved: false
           } = PathParam.new!("id", 42)
  end

  test "accepts explicit serialization options" do
    assert %PathParam{
             name: "id",
             value: ["blue", "black"],
             style: :label,
             explode: true,
             allow_reserved: true
           } =
             PathParam.new!("id", ["blue", "black"],
               style: :label,
               explode: true,
               allow_reserved: true
             )
  end

  test "does not inspect runtime values" do
    inspected = inspect(PathParam.new!("token", "secret-token", style: :matrix))

    refute inspected =~ "secret-token"
    assert inspected =~ ~s(name: "token")
    assert inspected =~ "style: :matrix"
  end

  test "serializes a path parameter with explicit keyword options" do
    opts = [
      path_params: [
        PathParam.new!("coords", ["blue", "black"], style: :matrix, explode: true)
      ]
    ]

    assert {:ok, env} =
             @middleware.call(
               %Env{url: "/items/{coords}", opts: opts},
               [],
               mode: :modern
             )

    assert env.url == "/items/;coords=blue;coords=black"
  end

  test "rejects document location as a hand-written option" do
    assert_raise ArgumentError, ~r/unknown keys \[:in\]/, fn ->
      PathParam.new!("color", "blue", in: :path)
    end
  end

  test "rejects string styles in hand-written keyword options" do
    assert_raise ArgumentError, ~r/expected :simple, :matrix, or :label/, fn ->
      PathParam.new!("color", "blue", style: "matrix")
    end
  end

  test "rejects non-path style atoms" do
    for style <- [:form, :space_delimited, :pipe_delimited, :deep_object, :cookie] do
      assert_raise ArgumentError, ~r/expected :simple, :matrix, or :label/, fn ->
        PathParam.new!("color", "blue", style: style)
      end
    end
  end

  test "rejects non-string names" do
    assert_raise ArgumentError, ~r/expected path parameter name to be a string/, fn ->
      PathParam.new!(:color, "blue")
    end
  end

  test "rejects non-boolean explode option" do
    assert_raise ArgumentError, ~r/expected :explode to be a boolean/, fn ->
      PathParam.new!("color", "blue", explode: "true")
    end
  end

  test "rejects non-boolean allow_reserved option" do
    assert_raise ArgumentError, ~r/expected :allow_reserved to be a boolean/, fn ->
      PathParam.new!("color", "blue", allow_reserved: 1)
    end
  end

  test "rejects atom-keyed maps as options" do
    assert_raise ArgumentError, ~r/expected path parameter options to be a keyword list/, fn ->
      PathParam.new!("color", "blue", %{style: :matrix})
    end
  end

  test "rejects string-keyed maps as options" do
    assert_raise ArgumentError, ~r/expected path parameter options to be a keyword list/, fn ->
      PathParam.new!("color", "blue", %{"style" => :matrix})
    end
  end

  test "rejects non-keyword lists as options" do
    assert_raise ArgumentError, ~r/expected a keyword list/, fn ->
      PathParam.new!("color", "blue", [:matrix])
    end
  end

  test "accepts nil values" do
    assert %PathParam{name: "color", value: nil, style: :matrix} =
             PathParam.new!("color", nil, style: :matrix)
  end

  test "encodes values with the unreserved set by default" do
    param = PathParam.new!("id", nil)

    assert PathParam.encode_value(param, "AZaz09-_.~") == "AZaz09-_.~"
    assert PathParam.encode_value(param, "a b/c?d#é%") == "a%20b%2Fc%3Fd%23%C3%A9%25"
  end

  test "encodes values while preserving allowed reserved path characters" do
    param = PathParam.new!("id", nil, allow_reserved: true)

    assert PathParam.encode_value(param, "!$&'()*+,;=:@") == "!$&'()*+,;=:@"
    assert PathParam.encode_value(param, "/?#[] é") == "%2F%3F%23%5B%5D%20%C3%A9"
    assert PathParam.encode_value(param, "") == ""
  end

  test "preserves valid percent triplets and escapes invalid ones when reserved are allowed" do
    param = PathParam.new!("id", nil, allow_reserved: true)

    assert PathParam.encode_value(param, "%20%2F%AF%af") == "%20%2F%AF%af"
    assert PathParam.encode_value(param, "%2G%zz%") == "%252G%25zz%25"
  end
end
