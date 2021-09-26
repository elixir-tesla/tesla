defmodule Tesla.OpenApiTest do
  use ExUnit.Case

  alias Tesla.OpenApi.Spec
  alias Tesla.OpenApi.Gen

  describe "Read & Gen" do
    test "Petstore" do
      Spec.read("test/support/openapi/petstore.json") |> Gen.gen()
    end

    test "Slack" do
      Spec.read("test/support/openapi/slack.json") |> Gen.gen()
    end

    test "Realworld" do
      Spec.read("test/support/openapi/realworld.json") |> Gen.gen()
    end
  end

  describe "__using__" do
    test "Petstore" do
      defmodule Petstore do
        use Tesla.OpenApi,
          spec: "test/support/openapi/petstore.json",
          dump: "tmp/petstore.exs"
      end
    end

    test "Slack" do
      defmodule Slack do
        use Tesla.OpenApi,
          spec: "test/support/openapi/slack.json",
          dump: "tmp/slack.exs"
      end
    end

    test "Realworld" do
      defmodule Realworld do
        use Tesla.OpenApi,
          spec: "test/support/openapi/realworld.json",
          dump: "tmp/realworld.exs"
      end
    end
  end
end
