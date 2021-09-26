defmodule Tesla.OpenApiTest do
  use ExUnit.Case

  describe "__using__" do
    test "Petstore" do
      defmodule Petstore do
        use Tesla.OpenApi, spec: "test/support/openapi/petstore.json"
      end
    end

    test "Slack" do
      defmodule Slack do
        use Tesla.OpenApi, spec: "test/support/openapi/slack.json"
      end
    end

    test "Realworld" do
      defmodule Realworld do
        use Tesla.OpenApi, spec: "test/support/openapi/realworld.json"
      end
    end
  end
end
