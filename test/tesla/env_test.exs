defmodule Tesla.EnvTest do
  use ExUnit.Case, async: true

  alias Tesla.Env

  test "merges private data maps from left to right" do
    assert Env.merge_private([
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
