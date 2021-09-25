defmodule Tesla.OpenApi.SpecTest do
  use ExUnit.Case

  import Tesla.OpenApiTest.Helpers

  alias Tesla.OpenApi3.{Prim, Union, Array, Object, Ref, Any}
  alias Tesla.OpenApi3.Model
  import Tesla.OpenApi3.Spec

  describe "from/1" do
    test "type: boolean" do
      assert from(%{"type" => "boolean"}) == %Prim{type: :boolean}
    end

    test "type: string" do
      assert from(%{"type" => "string"}) == %Prim{type: :binary}
    end

    test "type: integer" do
      assert from(%{"type" => "integer"}) == %Prim{type: :integer}
    end

    test "type: number" do
      assert from(%{"type" => "number"}) == %Prim{type: :number}
    end

    test "type: array" do
      assert from(%{"type" => ["null", "string"]}) == %Union{
               of: [
                 %Prim{type: :null},
                 %Prim{type: :binary}
               ]
             }
    end

    test "union: items" do
      assert from(%{
               "items" => [
                 %{"type" => "boolean"},
                 %{"type" => "integer"}
               ]
             }) == %Union{
               of: [
                 %Prim{type: :boolean},
                 %Prim{type: :integer}
               ]
             }
    end

    test "union: anyOf" do
      assert from(%{
               "anyOf" => [
                 %{
                   "type" => "object",
                   "properties" => %{
                     "id" => %{"type" => "integer"},
                     "name" => %{"type" => "string"}
                   }
                 },
                 %{
                   "type" => "object",
                   "properties" => %{
                     "id" => %{"type" => "string"},
                     "fullName" => %{"type" => "string"}
                   }
                 },
                 %{
                   "type" => "string"
                 },
                 %{
                   "type" => "array",
                   "items" => %{"type" => "integer"}
                 },
                 %{
                   "type" => "array",
                   "items" => %{"type" => "string"}
                 }
               ]
             }) == %Union{
               of: [
                 %Object{
                   props: %{
                     "id" => %Union{
                       of: [
                         %Prim{type: :binary},
                         %Prim{type: :integer}
                       ]
                     },
                     "name" => %Prim{type: :binary},
                     "fullName" => %Prim{type: :binary}
                   }
                 },
                 %Array{
                   of: %Union{
                     of: [
                       %Prim{type: :binary},
                       %Prim{type: :integer}
                     ]
                   }
                 },
                 %Prim{type: :binary}
               ]
             }
    end

    test "union: nested anyOf" do
      assert from(%{
               "anyOf" => [
                 %{"type" => "string"},
                 %{
                   "anyOf" => [
                     %{
                       "anyOf" => [
                         %{"type" => "boolean"},
                         %{"type" => "number"}
                       ]
                     },
                     %{"type" => "integer"}
                   ]
                 }
               ]
             }) == %Union{
               of: [
                 %Prim{type: :boolean},
                 %Prim{type: :number},
                 %Prim{type: :integer},
                 %Prim{type: :binary}
               ]
             }
    end

    test "Object" do
      assert from(%{
               "type" => "object",
               "properties" => %{
                 "id" => %{"type" => "integer"},
                 "name" => %{"type" => "string"}
               }
             }) == %Object{
               props: %{
                 "id" => %Prim{type: :integer},
                 "name" => %Prim{type: :binary}
               }
             }

      assert from(%{"type" => "object"}) == %Object{props: %{}}

      assert from(%{
               "type" => "object",
               "allOf" => [
                 %{"properties" => %{"id" => %{"type" => "integer"}}},
                 %{"properties" => %{"name" => %{"type" => "string"}}}
               ]
             }) == %Object{
               props: %{
                 "id" => %Prim{type: :integer},
                 "name" => %Prim{type: :binary}
               }
             }
    end

    test "Array" do
      assert from(%{"type" => "array", "items" => %{"type" => "string"}}) == %Array{
               of: %Prim{type: :binary}
             }

      assert from(%{"type" => "array"}) == %Array{of: %Any{}}
      assert from(%{"items" => %{"type" => "integer"}}) == %Array{of: %Prim{type: :integer}}
    end

    test "Ref" do
      load(%{
        "path" => %{
          "to" => [
            %{"value" => %{"type" => "integer"}}
          ]
        }
      })

      assert from(%{"$ref" => "#/definitions/Pet"}) == %Ref{name: "Pet", ref: "#/definitions/Pet"}

      assert from(%{"$ref" => "#/components/schemas/Pet"}) == %Ref{
               name: "Pet",
               ref: "#/components/schemas/Pet"
             }

      assert from(%{"$ref" => "#/path/to/0/value"}) == %Prim{type: :integer}
    end

    test "Any" do
      assert from(%{}) == %Any{}
      assert from(%{"additionalProperties" => false}) == %Any{}
    end
  end
end
