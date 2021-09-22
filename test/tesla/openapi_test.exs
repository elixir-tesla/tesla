defmodule Tesla.OpenApiTest.Helpers do
  alias Tesla.OpenApi

  defmacro assert_quoted(code, do: body) do
    quote do
      a = unquote(code)
      b = unquote(render(body))
      assert a == b, message: "Assert failed\n\n#{a}\n\nis not equal to\n\n#{b}"
    end
  end

  def type(field, spec \\ %{}), do: render(OpenApi.type(field, spec))

  def model(field, spec \\ %{}), do: render(OpenApi.model("t", field, spec))

  def encode(field, spec \\ %{}),
    do: render(OpenApi.encode(field, Macro.var(:x, Tesla.OpenApi), spec))

  def decode(field, spec \\ %{}),
    do: render(OpenApi.decode(field, Macro.var(:x, Tesla.OpenApi), spec))

  def operation(method, path, op, spec \\ %{}),
    do: render(OpenApi.operation(method, path, op, spec))

  def render(code) do
    code
    |> Macro.to_string()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  end
end

defmodule Tesla.OpenApiTest do
  use ExUnit.Case

  import Tesla.OpenApiTest.Helpers

  setup do
    :erlang.put(:caller, X)
    :ok
  end

  describe "Specs" do
    test "Petstore" do
      compile("test/support/openapi/petstore.json")
    end

    test "Slack" do
      compile("test/support/openapi/slack.json")
    end

    test "Realworld" do
      compile("test/support/openapi/realworld.json")
    end

    defp compile(spec) do
      mod = {:__aliases__, [alias: false], [:"M#{:rand.uniform(100_000)}"]}

      code =
        quote do
          defmodule unquote(mod) do
            use Tesla.OpenApi, spec: unquote(spec)
          end
        end

      assert [{_mod, _bin} | _] = Code.compile_quoted(code)
    end
  end

  describe "Schemas" do
    test "string schema" do
      schema = %{"type" => "string"}

      assert type(schema) == "binary"
      assert type({"ref", schema}) == "X.ref()"

      assert model(schema) == "@type t :: binary"

      assert encode(schema) == "x"
      assert encode({"ref", schema}) == "x"

      assert decode(schema) == "Tesla.OpenApi.decode_binary(x)"
      assert decode({"ref", schema}) == "Tesla.OpenApi.decode_binary(x)"
    end

    test "integer schema" do
      schema = %{"type" => "integer"}

      assert type(schema) == "integer"
      assert type({"ref", schema}) == "X.ref()"

      assert model(schema) == "@type t :: integer"

      assert encode(schema) == "x"
      assert encode({"ref", schema}) == "x"

      assert decode(schema) == "Tesla.OpenApi.decode_integer(x)"
      assert decode({"ref", schema}) == "Tesla.OpenApi.decode_integer(x)"
    end

    test "array of strings schema" do
      schema = %{"type" => "array", "items" => %{"type" => "string"}}

      assert type(schema) == "[binary]"
      assert type({"ref", schema}) == "X.Ref.t()"

      assert_quoted model(schema) do
        defmodule T do
          @moduledoc ""
          @type t :: [binary]
          def decode(data) do
            Tesla.OpenApi.decode_list(data, fn data -> Tesla.OpenApi.decode_binary(data) end)
          end

          def encode(data) do
            Tesla.OpenApi.encode_list(data, fn item -> item end)
          end
        end
      end

      assert_quoted encode(schema) do
        Tesla.OpenApi.encode_list(x, fn item -> item end)
      end

      assert_quoted encode({"ref", schema}) do
        X.Ref.encode(x)
      end

      assert_quoted decode(schema) do
        Tesla.OpenApi.decode_list(x, fn data -> Tesla.OpenApi.decode_binary(data) end)
      end

      assert_quoted decode({"ref", schema}) do
        X.Ref.decode(x)
      end
    end

    test "unknown array schema" do
      schema = %{"type" => "array"}

      assert type(schema) == "list"
      assert type({"ref", schema}) == "X.Ref.t()"

      assert_quoted model(schema) do
        defmodule T do
          @moduledoc ""
          @type t :: list
          def decode(data), do: Tesla.OpenApi.decode_list(data)
          def encode(data), do: data
        end
      end

      assert encode(schema) == "x"
      assert encode({"ref", schema}) == "X.Ref.encode(x)"

      assert_quoted decode(schema) do
        Tesla.OpenApi.decode_list(x)
      end

      assert_quoted decode({"ref", schema}) do
        X.Ref.decode(x)
      end
    end

    test "oneoff items with schemas" do
      schema = %{"items" => [%{"type" => "integer"}, %{"type" => "string"}]}
      assert type(schema) == "integer | binary"

      assert_quoted model(schema) do
        defmodule T do
          @moduledoc ""
          @type t :: integer | binary
          def decode(data) do
            with {:error, _} <- Tesla.OpenApi.decode_integer(data),
                 {:error, _} <- Tesla.OpenApi.decode_binary(data) do
              {:error, :invalid_value}
            end
          end

          def encode(data) do
            data
          end
        end
      end

      assert encode(schema) == "x"

      assert_quoted decode(schema) do
        with {:error, _} <- Tesla.OpenApi.decode_integer(x),
             {:error, _} <- Tesla.OpenApi.decode_binary(x) do
          {:error, :invalid_value}
        end
      end
    end

    test "object with properties" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "id" => %{"type" => "integer"}
        }
      }

      assert type(schema) == "%{id: integer, name: binary}"
      assert type({"ref", schema}) == "X.Ref.t()"

      assert_quoted model(schema) do
        defmodule T do
          @moduledoc ""
          defstruct id: nil, name: nil
          @type t :: %__MODULE__{id: integer, name: binary}
          def decode(data) do
            with {:ok, id} <- Tesla.OpenApi.decode_integer(data["id"]),
                 {:ok, name} <- Tesla.OpenApi.decode_binary(data["name"]) do
              {:ok, %__MODULE__{id: id, name: name}}
            end
          end

          def encode(data) do
            %{"id" => data.id, "name" => data.name}
          end
        end
      end
    end

    # test "object without properties"

    test "allof" do
      schema = %{
        "allOf" => [
          %{"properties" => %{"name" => %{"type" => "string"}}},
          %{"properties" => %{"id" => %{"type" => "integer"}}}
        ]
      }

      assert type(schema) == "%{id: integer, name: binary}"
      assert type({"ref", schema}) == "X.Ref.t()"

      assert_quoted model(schema) do
        defmodule T do
          @moduledoc ""
          defstruct id: nil, name: nil
          @type t :: %__MODULE__{id: integer, name: binary}
          def decode(data) do
            with {:ok, id} <- Tesla.OpenApi.decode_integer(data["id"]),
                 {:ok, name} <- Tesla.OpenApi.decode_binary(data["name"]) do
              {:ok, %__MODULE__{id: id, name: name}}
            end
          end

          def encode(data) do
            %{"id" => data.id, "name" => data.name}
          end
        end
      end
    end
  end

  describe "Operations" do
    test "encode name" do
      op = %{
        "operationId" => "deeply.nested.function",
        "responses" => []
      }

      assert_quoted operation("get", "/", op) do
        @doc ""
        @spec deeply_nested_function(Tesla.Client.t()) :: {:error, any}
        def deeply_nested_function(client \\ new()) do
          case Tesla.get(client, "/") do
            {:error, error} -> {:error, error}
          end
        end

        defoverridable(deeply_nested_function: 1)
      end
    end

    test "params" do
      op = %{
        "operationId" => "one",
        "parameters" => [
          %{"name" => "id", "in" => "path", "type" => "integer"},
          %{"name" => "limit", "in" => "query", "type" => "integer"},
          %{"name" => "sort", "in" => "query", "type" => "string"}
        ],
        "responses" => []
      }

      assert_quoted operation("get", "/{id}", op) do
        @doc ""
        @spec one(Tesla.Client.t(), integer, [opt]) :: {:error, any}
              when opt: {:limit, integer} | {:sort, binary}
        def one(client \\ new(), id, query \\ []) do
          case Tesla.get(client, "/:id",
                 query: Tesla.OpenApi.encode_query(query, limit: nil, sort: nil),
                 opts: [path_params: [id: id]]
               ) do
            {:error, error} -> {:error, error}
          end
        end

        defoverridable(one: 3)
      end
    end

    test "referenced params" do
      spec = %{
        "paths" => %{
          "/one/{id}" => %{
            "get" => %{
              "operationId" => "one",
              "parameters" => [
                %{
                  "name" => "id",
                  "in" => "path",
                  "schema" => %{"type" => "integer"}
                }
              ],
              "responses" => []
            }
          },
          "/two/{id}" => %{
            "get" =>
              op = %{
                "operationId" => "two",
                "parameters" => [
                  %{"$ref" => "#/paths/~1one~1%7Bid%7D/get/parameters/0"}
                ],
                "responses" => []
              }
          }
        }
      }

      assert_quoted operation("get", "/two/{id}", op, spec) do
        @doc ""
        @spec two(Tesla.Client.t(), integer) :: {:error, any}
        def two(client \\ new(), id) do
          case Tesla.get(client, "/two/:id", opts: [path_params: [id: id]]) do
            {:error, error} -> {:error, error}
          end
        end

        defoverridable(two: 2)
      end
    end
  end

  describe "References" do
    import Tesla.OpenApi, only: [dereference: 2]

    test "definition referenc (v2)" do
      spec = %{
        "definitions" => %{
          "Pet" => %{"type" => "object"}
        }
      }

      assert dereference("#/definitions/Pet", spec) == {"Pet", %{"type" => "object"}}
    end

    test "component reference (v3)" do
      spec = %{
        "components" => %{
          "schemas" => %{
            "Pet" => %{"type" => "object"}
          }
        }
      }

      assert dereference("#/components/schemas/Pet", spec) == {"Pet", %{"type" => "object"}}
    end

    test "any reference" do
      spec = %{
        "paths" => %{
          "/posts/{postId}/comments/{commentId}/like" => %{
            "delete" => %{
              "parameters" => [
                %{},
                %{
                  "schema" => %{"type" => "integer"}
                },
                %{}
              ]
            }
          }
        }
      }

      ref =
        "#/paths/~1posts~1%7BpostId%7D~1comments~1%7BcommentId%7D~1like/delete/parameters/1/schema"

      assert dereference(ref, spec) == %{"type" => "integer"}
    end
  end
end
