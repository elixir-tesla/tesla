defmodule Tesla.OpenAPI.HeaderParamTest do
  use ExUnit.Case, async: true

  alias Tesla.OpenAPI.HeaderParam

  test "uses default serialization options" do
    assert %HeaderParam{
             name: "X-Token",
             style: :simple,
             explode: false
           } = HeaderParam.new!("X-Token")
  end

  test "accepts explicit serialization options" do
    assert %HeaderParam{
             name: "X-Token",
             style: :simple,
             explode: true
           } =
             HeaderParam.new!("X-Token",
               style: :simple,
               explode: true
             )
  end

  test "rejects document location as a hand-written option" do
    assert_raise ArgumentError, ~r/unknown keys \[:in\]/, fn ->
      HeaderParam.new!("X-Token", in: :header)
    end
  end

  test "rejects allow_reserved as a header option" do
    assert_raise ArgumentError, ~r/unknown keys \[:allow_reserved\]/, fn ->
      HeaderParam.new!("X-Token", allow_reserved: true)
    end
  end

  test "rejects runtime values in the parameter definition" do
    assert_raise ArgumentError, ~r/expected header parameter options to be a keyword list/, fn ->
      HeaderParam.new!("X-Token", "blue")
    end
  end

  test "rejects string styles in hand-written keyword options" do
    assert_raise ArgumentError, ~r/expected :simple/, fn ->
      HeaderParam.new!("X-Token", style: "simple")
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
        HeaderParam.new!("X-Token", style: style)
      end
    end
  end

  test "rejects non-string names" do
    assert_raise ArgumentError, ~r/expected header parameter name to be a string/, fn ->
      HeaderParam.new!(:token)
    end
  end

  test "rejects non-boolean explode option" do
    assert_raise ArgumentError, ~r/expected header parameter :explode to be a boolean/, fn ->
      HeaderParam.new!("X-Token", explode: "true")
    end
  end

  test "rejects atom-keyed maps as options" do
    assert_raise ArgumentError, ~r/expected header parameter options to be a keyword list/, fn ->
      HeaderParam.new!("X-Token", %{style: :simple})
    end
  end

  test "rejects string-keyed maps as options" do
    assert_raise ArgumentError, ~r/expected header parameter options to be a keyword list/, fn ->
      HeaderParam.new!("X-Token", %{"style" => :simple})
    end
  end

  test "rejects non-keyword lists as options" do
    assert_raise ArgumentError, ~r/expected a keyword list/, fn ->
      HeaderParam.new!("X-Token", [:simple])
    end
  end
end
