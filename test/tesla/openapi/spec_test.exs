defmodule Tesla.OpenApi.SpecTest do
  use ExUnit.Case

  alias Tesla.OpenApi.{Prim, Union, Array, Object, Ref, Any}
  alias Tesla.OpenApi.{Operation, Param, Response}
  alias Tesla.OpenApi.Context
  import Tesla.OpenApi.Spec

  describe "schema/1" do
    test "type: boolean" do
      assert schema(%{"type" => "boolean"}) == %Prim{type: :boolean}
    end

    test "type: string" do
      assert schema(%{"type" => "string"}) == %Prim{type: :binary}
    end

    test "type: integer" do
      assert schema(%{"type" => "integer"}) == %Prim{type: :integer}
    end

    test "type: number" do
      assert schema(%{"type" => "number"}) == %Prim{type: :number}
    end

    test "type: array" do
      assert schema(%{"type" => ["null", "string"]}) == %Union{
               of: [
                 %Prim{type: :null},
                 %Prim{type: :binary}
               ]
             }
    end

    test "union: items" do
      assert schema(%{
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
      assert schema(%{
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
      assert schema(%{
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

    test "object with properties" do
      assert schema(%{
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
    end

    test "object without properties" do
      assert schema(%{"type" => "object"}) == %Object{props: %{}}
    end

    test "object with allOf" do
      assert schema(%{
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

    test "object with allOf and references" do
      spec = %{
        "definitions" => %{
          "Pet" => %{
            "type" => "object",
            "allOf" => [
              %{
                "$ref" => "#/definitions/NewPet"
              },
              %{
                "required" => [
                  "id"
                ],
                "properties" => %{
                  "id" => %{
                    "type" => "integer",
                    "format" => "int64"
                  }
                }
              }
            ]
          },
          "NewPet" => %{
            "type" => "object",
            "required" => [
              "name"
            ],
            "properties" => %{
              "name" => %{
                "type" => "string"
              },
              "tag" => %{
                "type" => "string"
              }
            }
          }
        }
      }

      Context.put_spec(spec)

      assert schema(spec["definitions"]["NewPet"]) == %Object{
               props: %{
                 "name" => %Prim{type: :binary},
                 "tag" => %Prim{type: :binary}
               }
             }

      assert schema(spec["definitions"]["Pet"]) == %Object{
               props: %{
                 "id" => %Prim{type: :integer},
                 "name" => %Prim{type: :binary},
                 "tag" => %Prim{type: :binary}
               }
             }
    end

    test "Array" do
      assert schema(%{"type" => "array", "items" => %{"type" => "string"}}) == %Array{
               of: %Prim{type: :binary}
             }

      assert schema(%{"type" => "array"}) == %Array{of: %Any{}}
      assert schema(%{"items" => %{"type" => "integer"}}) == %Array{of: %Prim{type: :integer}}
    end

    test "Ref" do
      Context.put_spec(%{
        "path" => %{
          "to" => [
            %{"value" => %{"type" => "integer"}}
          ]
        }
      })

      assert schema(%{"$ref" => "#/definitions/Pet"}) == %Ref{
               name: "Pet",
               ref: "#/definitions/Pet"
             }

      assert schema(%{"$ref" => "#/components/schemas/Pet"}) == %Ref{
               name: "Pet",
               ref: "#/components/schemas/Pet"
             }

      assert schema(%{"$ref" => "#/path/to/0/value"}) == %Prim{type: :integer}
    end

    test "Any" do
      assert schema(%{}) == %Any{}
      assert schema(%{"additionalProperties" => false}) == %Any{}
    end

    test "schema wrapped" do
      assert schema(%{"schema" => %{"type" => "integer"}}) == %Prim{type: :integer}
    end
  end

  describe "operations/1" do
    test "load operation" do
      spec = %{
        "paths" => %{
          "/pets" => %{
            "get" => %{
              "operationId" => "findPets",
              "summary" => "Find pets",
              "description" => "Find all pets",
              "parameters" => [
                %{
                  "in" => "query",
                  "items" => %{"type" => "string"},
                  "name" => "tags",
                  "type" => "array"
                },
                %{
                  "description" => "maximum number of results to return",
                  "in" => "query",
                  "name" => "limit",
                  "type" => "integer"
                }
              ],
              "requestBody" => %{
                "required" => true,
                "content" => %{
                  "application/json" => %{
                    "schema" => %{
                      "type" => "integer"
                    }
                  }
                }
              },
              "responses" => %{
                "200" => %{
                  "schema" => %{
                    "items" => %{"$ref" => "#/definitions/Pet"},
                    "type" => "array"
                  }
                },
                "default" => %{
                  "description" => "unexpected error",
                  "schema" => %{"$ref" => "#/definitions/ErrorModel"}
                }
              }
            }
          }
        }
      }

      assert operations(spec) == [
               %Operation{
                 id: "findPets",
                 summary: "Find pets",
                 description: "Find all pets",
                 method: "get",
                 path: "/pets",
                 query_params: [
                   %Param{name: "tags", schema: %Array{of: %Prim{type: :binary}}},
                   %Param{name: "limit", schema: %Prim{type: :integer}}
                 ],
                 request_body: %Prim{type: :integer},
                 responses: [
                   %Response{
                     code: 200,
                     schema: %Array{of: %Ref{name: "Pet", ref: "#/definitions/Pet"}}
                   },
                   %Response{
                     code: :default,
                     schema: %Ref{name: "ErrorModel", ref: "#/definitions/ErrorModel"}
                   }
                 ]
               }
             ]
    end
  end
end
