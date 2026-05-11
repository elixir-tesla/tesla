defmodule Tesla.HeaderParamTest do
  use ExUnit.Case, async: true

  alias Tesla.HeaderParam

  defmodule TestFilter do
    defstruct [:role, :id]
  end

  test "uses default serialization options" do
    assert %HeaderParam{
             name: "X-Token",
             value: 42,
             style: :simple,
             explode: false
           } = HeaderParam.new!("X-Token", 42)
  end

  test "accepts explicit serialization options" do
    assert %HeaderParam{
             name: "X-Token",
             value: [R: 100],
             style: :simple,
             explode: true
           } =
             HeaderParam.new!("X-Token", [R: 100],
               style: :simple,
               explode: true
             )
  end

  test "does not inspect runtime values" do
    inspected = inspect(HeaderParam.new!("X-Token", "secret-token"))

    refute inspected =~ "secret-token"
    assert inspected =~ ~s(name: "X-Token")
    assert inspected =~ "style: :simple"
  end

  describe "OpenAPI style examples" do
    test "simple style with explode false" do
      assert HeaderParam.new!("color", nil) |> HeaderParam.to_header() == {"color", ""}
      assert HeaderParam.new!("color", "blue") |> HeaderParam.to_header() == {"color", "blue"}

      assert HeaderParam.new!("color", ["blue", "black", "brown"]) |> HeaderParam.to_header() ==
               {"color", "blue,black,brown"}

      assert HeaderParam.new!("color", R: 100, G: 200, B: 150) |> HeaderParam.to_header() ==
               {"color", "R,100,G,200,B,150"}
    end

    test "simple style with explode true" do
      assert HeaderParam.new!("color", nil, explode: true) |> HeaderParam.to_header() ==
               {"color", ""}

      assert HeaderParam.new!("color", "blue", explode: true) |> HeaderParam.to_header() ==
               {"color", "blue"}

      assert HeaderParam.new!("color", ["blue", "black", "brown"], explode: true)
             |> HeaderParam.to_header() ==
               {"color", "blue,black,brown"}

      assert HeaderParam.new!("color", [R: 100, G: 200, B: 150], explode: true)
             |> HeaderParam.to_header() ==
               {"color", "R=100,G=200,B=150"}
    end
  end

  test "converts to a raw Tesla header tuple" do
    assert HeaderParam.new!("X-Token", [12_345_678, 90099]) |> HeaderParam.to_header() ==
             {"X-Token", "12345678,90099"}
  end

  test "does not percent-encode header values" do
    assert HeaderParam.new!("X-Token", "a/b c#d%zz|é") |> HeaderParam.to_header() ==
             {"X-Token", "a/b c#d%zz|é"}
  end

  test "supports struct values as objects" do
    header =
      HeaderParam.new!("X-Filter", %TestFilter{role: "admin", id: 5}, explode: true)
      |> HeaderParam.to_header()

    assert header in [
             {"X-Filter", "id=5,role=admin"},
             {"X-Filter", "role=admin,id=5"}
           ]
  end

  test "serializes empty arrays and objects as empty values" do
    assert HeaderParam.new!("X-Empty", []) |> HeaderParam.to_header() == {"X-Empty", ""}
    assert HeaderParam.new!("X-Empty", %{}) |> HeaderParam.to_header() == {"X-Empty", ""}
  end

  test "accepts nil values" do
    assert %HeaderParam{name: "X-Token", value: nil} = HeaderParam.new!("X-Token", nil)
  end

  test "rejects document location as a hand-written option" do
    assert_raise ArgumentError, ~r/unknown keys \[:in\]/, fn ->
      HeaderParam.new!("X-Token", "blue", in: :header)
    end
  end

  test "rejects allow_reserved as a header option" do
    assert_raise ArgumentError, ~r/unknown keys \[:allow_reserved\]/, fn ->
      HeaderParam.new!("X-Token", "blue", allow_reserved: true)
    end
  end

  test "rejects string styles in hand-written keyword options" do
    assert_raise ArgumentError, ~r/expected :simple/, fn ->
      HeaderParam.new!("X-Token", "blue", style: "simple")
    end
  end

  test "rejects non-header style atoms" do
    for style <- [
          :matrix,
          :label,
          :form,
          :space_delimited,
          :pipe_delimited,
          :deep_object,
          :cookie
        ] do
      assert_raise ArgumentError, ~r/expected :simple/, fn ->
        HeaderParam.new!("X-Token", "blue", style: style)
      end
    end
  end

  test "rejects non-string names" do
    assert_raise ArgumentError, ~r/expected header parameter name to be a string/, fn ->
      HeaderParam.new!(:token, "blue")
    end
  end

  test "rejects non-boolean explode option" do
    assert_raise ArgumentError, ~r/expected header parameter :explode to be a boolean/, fn ->
      HeaderParam.new!("X-Token", "blue", explode: "true")
    end
  end

  test "rejects atom-keyed maps as options" do
    assert_raise ArgumentError, ~r/expected header parameter options to be a keyword list/, fn ->
      HeaderParam.new!("X-Token", "blue", %{style: :simple})
    end
  end

  test "rejects string-keyed maps as options" do
    assert_raise ArgumentError, ~r/expected header parameter options to be a keyword list/, fn ->
      HeaderParam.new!("X-Token", "blue", %{"style" => :simple})
    end
  end

  test "rejects non-keyword lists as options" do
    assert_raise ArgumentError, ~r/expected a keyword list/, fn ->
      HeaderParam.new!("X-Token", "blue", [:simple])
    end
  end
end
