defmodule Tesla.OpenAPI.CookieParamTest do
  use ExUnit.Case, async: true

  alias Tesla.OpenAPI.CookieParam

  test "uses OpenAPI compatibility defaults" do
    assert %CookieParam{
             name: "color",
             style: :form,
             explode: true,
             allow_reserved: false
           } = CookieParam.new!("color")
  end

  test "defaults explode to false for cookie style" do
    assert %CookieParam{explode: false} = CookieParam.new!("color", style: :cookie)
  end

  test "accepts explicit serialization options" do
    assert %CookieParam{
             name: "color",
             style: :form,
             explode: false,
             allow_reserved: true
           } =
             CookieParam.new!("color",
               style: :form,
               explode: false,
               allow_reserved: true
             )
  end

  test "rejects document location as a hand-written option" do
    assert_raise ArgumentError, ~r/unknown keys \[:in\]/, fn ->
      CookieParam.new!("session_id", in: :cookie)
    end
  end

  test "rejects runtime values in the parameter definition" do
    assert_raise ArgumentError, ~r/expected cookie parameter options to be a keyword list/, fn ->
      CookieParam.new!("session_id", "abc123")
    end
  end

  test "rejects string styles in hand-written keyword options" do
    assert_raise ArgumentError, ~r/expected :form or :cookie/, fn ->
      CookieParam.new!("session_id", style: "cookie")
    end
  end

  test "rejects non-cookie style atoms" do
    for style <- [
          :matrix,
          :label,
          :simple,
          :space_delimited,
          :pipe_delimited,
          :deep_object
        ] do
      assert_raise ArgumentError, ~r/expected :form or :cookie/, fn ->
        CookieParam.new!("session_id", style: style)
      end
    end
  end

  test "rejects non-string names" do
    assert_raise ArgumentError, ~r/expected cookie parameter name to be a string/, fn ->
      CookieParam.new!(:session_id)
    end
  end

  test "rejects non-boolean explode option" do
    assert_raise ArgumentError, ~r/expected cookie parameter :explode to be a boolean/, fn ->
      CookieParam.new!("session_id", explode: "true")
    end
  end

  test "rejects non-boolean allow_reserved option" do
    assert_raise ArgumentError,
                 ~r/expected cookie parameter :allow_reserved to be a boolean/,
                 fn ->
                   CookieParam.new!("session_id", allow_reserved: "true")
                 end
  end

  test "rejects atom-keyed maps as options" do
    assert_raise ArgumentError, ~r/expected cookie parameter options to be a keyword list/, fn ->
      CookieParam.new!("session_id", %{style: :cookie})
    end
  end

  test "rejects string-keyed maps as options" do
    assert_raise ArgumentError, ~r/expected cookie parameter options to be a keyword list/, fn ->
      CookieParam.new!("session_id", %{"style" => :cookie})
    end
  end

  test "rejects non-keyword lists as options" do
    assert_raise ArgumentError, ~r/expected a keyword list/, fn ->
      CookieParam.new!("session_id", [:cookie])
    end
  end
end
