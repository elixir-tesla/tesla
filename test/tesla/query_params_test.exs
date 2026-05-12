defmodule Tesla.QueryParamsTest do
  use ExUnit.Case, async: true

  alias Tesla.QueryParam
  alias Tesla.QueryParams

  test "keeps query parameter definitions in declaration order" do
    definitions = [
      QueryParam.new!("page"),
      QueryParam.new!("ids", style: :pipe_delimited)
    ]

    query_params = QueryParams.new!(definitions)

    assert QueryParams.definitions(query_params) == definitions
  end

  test "indexes query parameter definitions by name" do
    query_params =
      QueryParams.new!([
        QueryParam.new!("page"),
        QueryParam.new!("ids", style: :pipe_delimited)
      ])

    assert {:ok, %QueryParam{name: "page", style: :form}} =
             QueryParams.fetch(query_params, "page")

    assert {:ok, %QueryParam{name: "ids", style: :pipe_delimited}} =
             QueryParams.fetch(query_params, "ids")

    assert QueryParams.fetch(query_params, "missing") == :error
  end

  test "stores and fetches query params from request private data" do
    query_params = QueryParams.new!([QueryParam.new!("page")])
    private = QueryParams.put_private(%{existing: true}, query_params)

    assert private.existing
    assert QueryParams.fetch_private(private) == {:ok, query_params}
  end

  test "ignores invalid private query params data" do
    assert QueryParams.fetch_private(%{tesla_query_params: :invalid}) == :error
    assert QueryParams.fetch_private(%{}) == :error
  end

  test "raises on duplicate query parameter definitions" do
    assert_raise ArgumentError, ~r/duplicate query parameter "page"/, fn ->
      QueryParams.new!([
        QueryParam.new!("page"),
        QueryParam.new!("page", style: :pipe_delimited)
      ])
    end
  end

  test "raises when definitions are not query params" do
    assert_raise ArgumentError,
                 ~r/expected query parameter definitions to be Tesla.QueryParam structs/,
                 fn ->
                   QueryParams.new!([%{name: "page"}])
                 end
  end
end
