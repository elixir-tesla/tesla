defmodule Tesla.OpenAPI.HeaderParamsTest do
  use ExUnit.Case, async: true

  alias Tesla.OpenAPI.HeaderParam
  alias Tesla.OpenAPI.HeaderParams

  defmodule TestFilter do
    defstruct [:role, :id]
  end

  test "keeps header parameter definitions in declaration order" do
    definitions = [
      HeaderParam.new!("X-Request-ID"),
      HeaderParam.new!("X-Filter", explode: true)
    ]

    header_params = HeaderParams.new!(definitions)

    assert HeaderParams.definitions(header_params) == definitions
  end

  test "indexes header parameter definitions by name" do
    header_params =
      HeaderParams.new!([
        HeaderParam.new!("X-Request-ID"),
        HeaderParam.new!("X-Filter", explode: true)
      ])

    assert {:ok, %HeaderParam{name: "X-Request-ID", style: :simple}} =
             HeaderParams.fetch(header_params, "X-Request-ID")

    assert {:ok, %HeaderParam{name: "X-Filter", explode: true}} =
             HeaderParams.fetch(header_params, "X-Filter")

    assert HeaderParams.fetch(header_params, "missing") == :error
  end

  describe "OpenAPI style examples" do
    test "simple style with explode false" do
      header_params = HeaderParams.new!([HeaderParam.new!("color")])

      assert HeaderParams.to_headers(header_params, %{"color" => nil}) == [{"color", ""}]
      assert HeaderParams.to_headers(header_params, %{"color" => "blue"}) == [{"color", "blue"}]

      assert HeaderParams.to_headers(header_params, %{
               "color" => ["blue", "black", "brown"]
             }) == [{"color", "blue,black,brown"}]

      assert HeaderParams.to_headers(header_params, %{
               "color" => [R: 100, G: 200, B: 150]
             }) == [{"color", "R,100,G,200,B,150"}]
    end

    test "simple style with explode true" do
      header_params = HeaderParams.new!([HeaderParam.new!("color", explode: true)])

      assert HeaderParams.to_headers(header_params, %{"color" => nil}) == [{"color", ""}]
      assert HeaderParams.to_headers(header_params, %{"color" => "blue"}) == [{"color", "blue"}]

      assert HeaderParams.to_headers(header_params, %{
               "color" => ["blue", "black", "brown"]
             }) == [{"color", "blue,black,brown"}]

      assert HeaderParams.to_headers(header_params, %{
               "color" => [R: 100, G: 200, B: 150]
             }) == [{"color", "R=100,G=200,B=150"}]
    end
  end

  test "converts request values to raw Tesla header tuples" do
    header_params =
      HeaderParams.new!([
        HeaderParam.new!("X-Token"),
        HeaderParam.new!("X-Request-ID")
      ])

    assert HeaderParams.to_headers(header_params, %{
             "X-Token" => [12_345_678, 90099],
             "X-Request-ID" => "req-123"
           }) == [
             {"X-Token", "12345678,90099"},
             {"X-Request-ID", "req-123"}
           ]
  end

  test "skips request values without matching definitions" do
    header_params = HeaderParams.new!([HeaderParam.new!("X-Token")])

    assert HeaderParams.to_headers(header_params, %{
             "X-Request-ID" => "req-123"
           }) == []
  end

  test "returns no headers for nil request values" do
    assert HeaderParams.new!([HeaderParam.new!("X-Token")])
           |> HeaderParams.to_headers(nil) == []
  end

  test "does not percent-encode header values" do
    header_params = HeaderParams.new!([HeaderParam.new!("X-Token")])

    assert HeaderParams.to_headers(header_params, %{"X-Token" => "a/b c#d%zz|é"}) ==
             [{"X-Token", "a/b c#d%zz|é"}]
  end

  test "supports struct values as objects" do
    header_params = HeaderParams.new!([HeaderParam.new!("X-Filter", explode: true)])

    headers =
      HeaderParams.to_headers(header_params, %{
        "X-Filter" => %TestFilter{role: "admin", id: 5}
      })

    assert headers in [
             [{"X-Filter", "id=5,role=admin"}],
             [{"X-Filter", "role=admin,id=5"}]
           ]
  end

  test "serializes empty arrays and objects as empty values" do
    header_params =
      HeaderParams.new!([
        HeaderParam.new!("X-Empty-Array"),
        HeaderParam.new!("X-Empty-Object")
      ])

    assert HeaderParams.to_headers(header_params, %{
             "X-Empty-Array" => [],
             "X-Empty-Object" => %{}
           }) == [
             {"X-Empty-Array", ""},
             {"X-Empty-Object", ""}
           ]
  end

  test "raises on duplicate header parameter definitions" do
    assert_raise ArgumentError, ~r/duplicate header parameter "X-Token"/, fn ->
      HeaderParams.new!([
        HeaderParam.new!("X-Token"),
        HeaderParam.new!("X-Token", explode: true)
      ])
    end
  end

  test "raises when definitions are not header params" do
    assert_raise ArgumentError,
                 ~r/expected header parameter definitions to be Tesla.OpenAPI.HeaderParam structs/,
                 fn ->
                   HeaderParams.new!([%{name: "X-Token"}])
                 end
  end

  test "raises when values are not a map" do
    header_params = HeaderParams.new!([HeaderParam.new!("X-Token")])

    assert_raise ArgumentError, ~r/expected header parameter values to be a map/, fn ->
      HeaderParams.to_headers(header_params, [{"X-Token", "secret"}])
    end
  end
end
