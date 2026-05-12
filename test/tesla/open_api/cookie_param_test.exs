defmodule Tesla.OpenAPI.CookieParamTest do
  use ExUnit.Case, async: true

  alias Tesla.OpenAPI.CookieParam

  defmodule TestFilter do
    defstruct [:role, :id]
  end

  test "uses OpenAPI compatibility defaults" do
    assert %CookieParam{
             name: "color",
             value: "blue",
             style: :form,
             explode: true,
             allow_reserved: false
           } = CookieParam.new!("color", "blue")
  end

  test "defaults explode to false for cookie style" do
    assert %CookieParam{explode: false} = CookieParam.new!("color", "blue", style: :cookie)
  end

  test "accepts explicit serialization options" do
    assert %CookieParam{
             name: "color",
             value: [R: 100],
             style: :form,
             explode: false,
             allow_reserved: true
           } =
             CookieParam.new!("color", [R: 100],
               style: :form,
               explode: false,
               allow_reserved: true
             )
  end

  test "does not inspect runtime values" do
    inspected = inspect(CookieParam.new!("session_id", "secret-token"))

    refute inspected =~ "secret-token"
    assert inspected =~ ~s(name: "session_id")
    assert inspected =~ "style: :form"
  end

  describe "OpenAPI form style examples" do
    test "form style with explode false" do
      assert CookieParam.new!("color", nil, explode: false) |> CookieParam.to_header() ==
               {"cookie", "color="}

      assert CookieParam.new!("color", "blue", explode: false) |> CookieParam.to_header() ==
               {"cookie", "color=blue"}

      assert CookieParam.new!("color", ["blue", "black", "brown"], explode: false)
             |> CookieParam.to_header() ==
               {"cookie", "color=blue,black,brown"}

      assert CookieParam.new!("color", [R: 100, G: 200, B: 150], explode: false)
             |> CookieParam.to_header() ==
               {"cookie", "color=R,100,G,200,B,150"}
    end

    test "form style with explode true" do
      assert CookieParam.new!("color", nil) |> CookieParam.to_header() ==
               {"cookie", "color="}

      assert CookieParam.new!("color", "blue") |> CookieParam.to_header() ==
               {"cookie", "color=blue"}

      assert CookieParam.new!("color", ["blue", "black", "brown"]) |> CookieParam.to_header() ==
               {"cookie", "color=blue&color=black&color=brown"}

      assert CookieParam.new!("color", R: 100, G: 200, B: 150) |> CookieParam.to_header() ==
               {"cookie", "R=100&G=200&B=150"}
    end
  end

  describe "OpenAPI cookie style examples" do
    test "cookie style with explode false" do
      param = CookieParam.new!("color", nil, style: :cookie, explode: false)
      assert CookieParam.to_header(param) == {"cookie", "color="}

      param = CookieParam.new!("color", "blue", style: :cookie, explode: false)
      assert CookieParam.to_header(param) == {"cookie", "color=blue"}

      param =
        CookieParam.new!("color", ["blue", "black", "brown"],
          style: :cookie,
          explode: false
        )

      assert CookieParam.to_header(param) == {"cookie", "color=blue,black,brown"}

      param =
        CookieParam.new!("color", [R: 100, G: 200, B: 150],
          style: :cookie,
          explode: false
        )

      assert CookieParam.to_header(param) == {"cookie", "color=R,100,G,200,B,150"}
    end

    test "cookie style with explode true" do
      param = CookieParam.new!("color", nil, style: :cookie, explode: true)
      assert CookieParam.to_header(param) == {"cookie", "color="}

      param = CookieParam.new!("color", "blue", style: :cookie, explode: true)
      assert CookieParam.to_header(param) == {"cookie", "color=blue"}

      param =
        CookieParam.new!("color", ["blue", "black", "brown"],
          style: :cookie,
          explode: true
        )

      expected = {"cookie", "color=blue; color=black; color=brown"}
      assert CookieParam.to_header(param) == expected

      param =
        CookieParam.new!("color", [R: 100, G: 200, B: 150],
          style: :cookie,
          explode: true
        )

      assert CookieParam.to_header(param) == {"cookie", "R=100; G=200; B=150"}
    end
  end

  test "converts multiple parameters to a raw Tesla cookie header tuple" do
    params = [
      CookieParam.new!("session_id", "abc123", style: :cookie, explode: true),
      CookieParam.new!("theme", "dark", style: :cookie, explode: true)
    ]

    expected = {"cookie", "session_id=abc123; theme=dark"}
    assert CookieParam.to_header(params) == expected
  end

  test "cookie style does not percent-encode names or values" do
    assert CookieParam.new!("raw name", "a/b c#d%zz|é", style: :cookie)
           |> CookieParam.to_header() ==
             {"cookie", "raw name=a/b c#d%zz|é"}
  end

  test "form style percent-encodes names and values" do
    assert CookieParam.new!("greeting name", "Hello, world!", style: :form)
           |> CookieParam.to_header() ==
             {"cookie", "greeting%20name=Hello%2C%20world%21"}
  end

  test "form style preserves reserved values and percent triples when allow_reserved is true" do
    assert CookieParam.new!("filter", "a/b?c#d%2B%", style: :form, allow_reserved: true)
           |> CookieParam.to_header() ==
             {"cookie", "filter=a/b?c#d%2B%25"}
  end

  test "supports struct values as objects" do
    header =
      CookieParam.new!("filter", %TestFilter{role: "admin", id: 5},
        style: :cookie,
        explode: true
      )
      |> CookieParam.to_header()

    assert header in [
             {"cookie", "id=5; role=admin"},
             {"cookie", "role=admin; id=5"}
           ]
  end

  test "serializes empty arrays and objects as empty cookie values" do
    assert CookieParam.new!("empty_array", []) |> CookieParam.to_header() ==
             {"cookie", "empty_array="}

    assert CookieParam.new!("empty_object", %{}) |> CookieParam.to_header() ==
             {"cookie", "empty_object="}
  end

  test "accepts nil values" do
    assert %CookieParam{name: "session_id", value: nil} = CookieParam.new!("session_id", nil)
  end

  test "rejects document location as a hand-written option" do
    assert_raise ArgumentError, ~r/unknown keys \[:in\]/, fn ->
      CookieParam.new!("session_id", "abc123", in: :cookie)
    end
  end

  test "rejects string styles in hand-written keyword options" do
    assert_raise ArgumentError, ~r/expected :form or :cookie/, fn ->
      CookieParam.new!("session_id", "abc123", style: "cookie")
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
        CookieParam.new!("session_id", "abc123", style: style)
      end
    end
  end

  test "rejects non-string names" do
    assert_raise ArgumentError, ~r/expected cookie parameter name to be a string/, fn ->
      CookieParam.new!(:session_id, "abc123")
    end
  end

  test "rejects non-boolean explode option" do
    assert_raise ArgumentError, ~r/expected cookie parameter :explode to be a boolean/, fn ->
      CookieParam.new!("session_id", "abc123", explode: "true")
    end
  end

  test "rejects non-boolean allow_reserved option" do
    assert_raise ArgumentError,
                 ~r/expected cookie parameter :allow_reserved to be a boolean/,
                 fn ->
                   CookieParam.new!("session_id", "abc123", allow_reserved: "true")
                 end
  end

  test "rejects atom-keyed maps as options" do
    assert_raise ArgumentError, ~r/expected cookie parameter options to be a keyword list/, fn ->
      CookieParam.new!("session_id", "abc123", %{style: :cookie})
    end
  end

  test "rejects string-keyed maps as options" do
    assert_raise ArgumentError, ~r/expected cookie parameter options to be a keyword list/, fn ->
      CookieParam.new!("session_id", "abc123", %{"style" => :cookie})
    end
  end

  test "rejects non-keyword lists as options" do
    assert_raise ArgumentError, ~r/expected a keyword list/, fn ->
      CookieParam.new!("session_id", "abc123", [:cookie])
    end
  end

  test "rejects non-cookie parameter values in header lists" do
    assert_raise ArgumentError,
                 ~r/expected cookie header to be a Tesla.OpenAPI.CookieParam struct/,
                 fn ->
                   CookieParam.to_header([
                     CookieParam.new!("session_id", "abc123"),
                     {"theme", "dark"}
                   ])
                 end
  end

  test "rejects non-cookie parameter header input" do
    assert_raise ArgumentError,
                 ~r/expected cookie header to be a Tesla.OpenAPI.CookieParam struct/,
                 fn ->
                   CookieParam.to_header(%{session_id: "abc123"})
                 end
  end
end
