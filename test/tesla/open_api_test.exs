defmodule Tesla.OpenAPITest do
  use ExUnit.Case, async: true

  alias Tesla.OpenAPI

  test "merges private data maps from left to right" do
    assert OpenAPI.merge_private([
             %{tesla_path_template: :template},
             %{tesla_path_params: :path_params},
             %{tesla_query_params: :query_params, tesla_path_params: :override}
           ]) == %{
             tesla_path_template: :template,
             tesla_path_params: :override,
             tesla_query_params: :query_params
           }
  end
end
