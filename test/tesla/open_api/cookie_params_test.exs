defmodule Tesla.OpenAPI.CookieParamsTest do
  use ExUnit.Case, async: true

  alias Tesla.OpenAPI.CookieParam
  alias Tesla.OpenAPI.CookieParams

  defmodule TestFilter do
    defstruct [:role, :id]
  end

  test "keeps cookie parameter definitions in declaration order" do
    definitions = [
      CookieParam.new!("session_id"),
      CookieParam.new!("theme", style: :cookie)
    ]

    cookie_params = CookieParams.new!(definitions)

    assert CookieParams.definitions(cookie_params) == definitions
  end

  test "indexes cookie parameter definitions by name" do
    cookie_params =
      CookieParams.new!([
        CookieParam.new!("session_id"),
        CookieParam.new!("theme", style: :cookie)
      ])

    assert {:ok, %CookieParam{name: "session_id", style: :form}} =
             CookieParams.fetch(cookie_params, "session_id")

    assert {:ok, %CookieParam{name: "theme", style: :cookie}} =
             CookieParams.fetch(cookie_params, "theme")

    assert CookieParams.fetch(cookie_params, "missing") == :error
  end

  describe "OpenAPI form style examples" do
    test "form style with explode false" do
      cookie_params = CookieParams.new!([CookieParam.new!("color", explode: false)])

      assert CookieParams.to_headers(cookie_params, %{"color" => nil}) == [
               {"cookie", "color="}
             ]

      assert CookieParams.to_headers(cookie_params, %{"color" => "blue"}) == [
               {"cookie", "color=blue"}
             ]

      assert CookieParams.to_headers(cookie_params, %{
               "color" => ["blue", "black", "brown"]
             }) == [{"cookie", "color=blue,black,brown"}]

      assert CookieParams.to_headers(cookie_params, %{
               "color" => [R: 100, G: 200, B: 150]
             }) == [{"cookie", "color=R,100,G,200,B,150"}]
    end

    test "form style with explode true" do
      cookie_params = CookieParams.new!([CookieParam.new!("color")])

      assert CookieParams.to_headers(cookie_params, %{"color" => nil}) == [
               {"cookie", "color="}
             ]

      assert CookieParams.to_headers(cookie_params, %{"color" => "blue"}) == [
               {"cookie", "color=blue"}
             ]

      assert CookieParams.to_headers(cookie_params, %{
               "color" => ["blue", "black", "brown"]
             }) == [{"cookie", "color=blue&color=black&color=brown"}]

      assert CookieParams.to_headers(cookie_params, %{
               "color" => [R: 100, G: 200, B: 150]
             }) == [{"cookie", "R=100&G=200&B=150"}]
    end
  end

  describe "OpenAPI cookie style examples" do
    test "cookie style with explode false" do
      cookie_params =
        CookieParams.new!([
          CookieParam.new!("color", style: :cookie, explode: false)
        ])

      assert CookieParams.to_headers(cookie_params, %{"color" => nil}) == [
               {"cookie", "color="}
             ]

      assert CookieParams.to_headers(cookie_params, %{"color" => "blue"}) == [
               {"cookie", "color=blue"}
             ]

      assert CookieParams.to_headers(cookie_params, %{
               "color" => ["blue", "black", "brown"]
             }) == [{"cookie", "color=blue,black,brown"}]

      assert CookieParams.to_headers(cookie_params, %{
               "color" => [R: 100, G: 200, B: 150]
             }) == [{"cookie", "color=R,100,G,200,B,150"}]
    end

    test "cookie style with explode true" do
      cookie_params =
        CookieParams.new!([
          CookieParam.new!("color", style: :cookie, explode: true)
        ])

      assert CookieParams.to_headers(cookie_params, %{"color" => nil}) == [
               {"cookie", "color="}
             ]

      assert CookieParams.to_headers(cookie_params, %{"color" => "blue"}) == [
               {"cookie", "color=blue"}
             ]

      assert CookieParams.to_headers(cookie_params, %{
               "color" => ["blue", "black", "brown"]
             }) == [{"cookie", "color=blue; color=black; color=brown"}]

      assert CookieParams.to_headers(cookie_params, %{
               "color" => [R: 100, G: 200, B: 150]
             }) == [{"cookie", "R=100; G=200; B=150"}]
    end
  end

  test "converts request values to a raw Tesla cookie header tuple" do
    cookie_params =
      CookieParams.new!([
        CookieParam.new!("session_id", style: :cookie, explode: true),
        CookieParam.new!("theme", style: :cookie, explode: true)
      ])

    assert CookieParams.to_headers(cookie_params, %{
             "session_id" => "abc123",
             "theme" => "dark"
           }) == [{"cookie", "session_id=abc123; theme=dark"}]
  end

  test "skips request values without matching definitions" do
    cookie_params = CookieParams.new!([CookieParam.new!("session_id")])

    assert CookieParams.to_headers(cookie_params, %{"theme" => "dark"}) == []
  end

  test "returns no headers for nil request values" do
    assert CookieParams.new!([CookieParam.new!("session_id")])
           |> CookieParams.to_headers(nil) == []
  end

  test "cookie style does not percent-encode names or values" do
    cookie_params = CookieParams.new!([CookieParam.new!("raw name", style: :cookie)])

    assert CookieParams.to_headers(cookie_params, %{"raw name" => "a/b c#d%zz|é"}) == [
             {"cookie", "raw name=a/b c#d%zz|é"}
           ]
  end

  test "form style percent-encodes names and values" do
    cookie_params = CookieParams.new!([CookieParam.new!("greeting name", style: :form)])

    assert CookieParams.to_headers(cookie_params, %{"greeting name" => "Hello, world!"}) == [
             {"cookie", "greeting%20name=Hello%2C%20world%21"}
           ]
  end

  test "form style preserves reserved values and percent triples when allow_reserved is true" do
    cookie_params =
      CookieParams.new!([
        CookieParam.new!("filter", style: :form, allow_reserved: true)
      ])

    assert CookieParams.to_headers(cookie_params, %{"filter" => "a/b?c#d%2B%"}) == [
             {"cookie", "filter=a/b?c#d%2B%25"}
           ]
  end

  test "supports struct values as objects" do
    cookie_params =
      CookieParams.new!([
        CookieParam.new!("filter", style: :cookie, explode: true)
      ])

    headers =
      CookieParams.to_headers(cookie_params, %{
        "filter" => %TestFilter{role: "admin", id: 5}
      })

    assert headers in [
             [{"cookie", "id=5; role=admin"}],
             [{"cookie", "role=admin; id=5"}]
           ]
  end

  test "serializes empty arrays and objects as empty cookie values" do
    cookie_params =
      CookieParams.new!([
        CookieParam.new!("empty_array"),
        CookieParam.new!("empty_object")
      ])

    assert CookieParams.to_headers(cookie_params, %{
             "empty_array" => [],
             "empty_object" => %{}
           }) == [{"cookie", "empty_array=; empty_object="}]
  end

  test "raises on duplicate cookie parameter definitions" do
    assert_raise ArgumentError, ~r/duplicate cookie parameter "session_id"/, fn ->
      CookieParams.new!([
        CookieParam.new!("session_id"),
        CookieParam.new!("session_id", style: :cookie)
      ])
    end
  end

  test "raises when definitions are not cookie params" do
    assert_raise ArgumentError,
                 ~r/expected cookie parameter definitions to be Tesla.OpenAPI.CookieParam structs/,
                 fn ->
                   CookieParams.new!([%{name: "session_id"}])
                 end
  end

  test "raises when values are not a map" do
    cookie_params = CookieParams.new!([CookieParam.new!("session_id")])

    assert_raise ArgumentError, ~r/expected cookie parameter values to be a map/, fn ->
      CookieParams.to_headers(cookie_params, [{"session_id", "abc123"}])
    end
  end
end
