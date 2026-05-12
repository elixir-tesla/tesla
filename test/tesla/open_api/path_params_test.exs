defmodule Tesla.OpenAPI.PathParamsTest do
  use ExUnit.Case, async: true

  alias Tesla.OpenAPI.PathParam
  alias Tesla.OpenAPI.PathParams

  test "indexes path parameter definitions by name" do
    path_params =
      PathParams.new!([
        PathParam.new!("id"),
        PathParam.new!("coords", style: :matrix, explode: true)
      ])

    assert {:ok, %PathParam{name: "id", style: :simple}} = PathParams.fetch(path_params, "id")

    assert {:ok, %PathParam{name: "coords", style: :matrix}} =
             PathParams.fetch(path_params, "coords")

    assert PathParams.fetch(path_params, "missing") == :error
  end

  test "stores and fetches path params from request private data" do
    path_params = PathParams.new!([PathParam.new!("id")])
    private = PathParams.put_private(%{existing: true}, path_params)

    assert private.existing
    assert PathParams.fetch_private(private) == {:ok, path_params}
  end

  test "ignores invalid private path params data" do
    assert PathParams.fetch_private(%{tesla_path_params: :invalid}) == :error
    assert PathParams.fetch_private(%{}) == :error
  end

  test "raises on duplicate path parameter definitions" do
    assert_raise ArgumentError, ~r/duplicate path parameter "id"/, fn ->
      PathParams.new!([
        PathParam.new!("id"),
        PathParam.new!("id", style: :matrix)
      ])
    end
  end

  test "raises when definitions are not path params" do
    assert_raise ArgumentError,
                 ~r/expected path parameter definitions to be Tesla.OpenAPI.PathParam structs/,
                 fn ->
                   PathParams.new!([%{name: "id"}])
                 end
  end
end
