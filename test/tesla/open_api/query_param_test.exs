defmodule Tesla.OpenAPI.QueryParamTest do
  use ExUnit.Case

  alias Tesla.OpenAPI.QueryParam

  test "builds a form query parameter by default" do
    assert %QueryParam{
             name: "id",
             style: :form,
             explode: true,
             allow_reserved: false
           } = QueryParam.new!("id")
  end

  test "defaults explode to false for non-form styles" do
    assert %QueryParam{explode: false} = QueryParam.new!("ids", style: :pipe_delimited)
    assert %QueryParam{explode: false} = QueryParam.new!("ids", style: :space_delimited)
    assert %QueryParam{explode: false} = QueryParam.new!("filter", style: :deep_object)
  end

  test "inspects static metadata" do
    inspected = inspect(QueryParam.new!("token", style: :deep_object))

    assert inspected =~ ~s(name: "token")
    assert inspected =~ "style: :deep_object"
  end

  test "rejects non-string names" do
    assert_raise ArgumentError, ~r/expected query parameter name to be a string/, fn ->
      QueryParam.new!(:id)
    end
  end

  test "rejects non-keyword options" do
    assert_raise ArgumentError, ~r/expected query parameter options to be a keyword list/, fn ->
      QueryParam.new!("id", %{style: :form})
    end
  end

  test "rejects string option keys" do
    assert_raise ArgumentError, ~r/expected a keyword list/, fn ->
      QueryParam.new!("id", [{"style", :form}])
    end
  end

  test "rejects unknown option keys" do
    assert_raise ArgumentError, ~r/unknown keys/, fn ->
      QueryParam.new!("id", style: :form, future_field: true)
    end
  end

  test "rejects unknown styles" do
    assert_raise ArgumentError, ~r/unknown query parameter style :matrix/, fn ->
      QueryParam.new!("id", style: :matrix)
    end
  end

  test "rejects string styles" do
    assert_raise ArgumentError, ~r/unknown query parameter style "form"/, fn ->
      QueryParam.new!("id", style: "form")
    end
  end

  test "rejects non-boolean explode" do
    assert_raise ArgumentError, ~r/expected query parameter :explode to be a boolean/, fn ->
      QueryParam.new!("id", explode: "true")
    end
  end

  test "rejects non-boolean allow_reserved" do
    assert_raise ArgumentError,
                 ~r/expected query parameter :allow_reserved to be a boolean/,
                 fn ->
                   QueryParam.new!("id", allow_reserved: "true")
                 end
  end

  test "encodes names with default query-name encoding" do
    assert QueryParam.encode_name("filter[role]") == "filter%5Brole%5D"
  end

  test "encodes values against the unreserved set by default" do
    param = QueryParam.new!("q")

    assert QueryParam.encode_value(param, "a/b c#d|") == "a%2Fb%20c%23d%7C"
  end

  test "preserves reserved values and percent triples when allow_reserved is true" do
    param = QueryParam.new!("q", allow_reserved: true)

    assert QueryParam.encode_value(param, "a/b?c#d%2Fe %zz|") ==
             "a/b?c#d%2Fe%20%25zz%7C"
  end

  test "preserves lowercase percent triples and escapes incomplete percent sequences" do
    param = QueryParam.new!("q", allow_reserved: true)

    assert QueryParam.encode_value(param, "%2f%") == "%2f%25"
  end
end
