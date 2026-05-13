defmodule Tesla.OpenAPI.QueryParamsTest do
  use ExUnit.Case, async: true

  alias Tesla.OpenAPI.QueryParam
  alias Tesla.OpenAPI.QueryParams

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
                 ~r/expected query parameter definitions to be Tesla.OpenAPI.QueryParam structs/,
                 fn ->
                   QueryParams.new!([%{name: "page"}])
                 end
  end
end
