defmodule Tesla.OpenApiTest.Helpers do
  alias Tesla.OpenApi

  defmodule Config do
    def op_name(name), do: name
    def generate?(_), do: true
  end

  defmacro assert_quoted(code, do: body) do
    quote do
      a = render(unquote(code))
      b = unquote(render(body))
      assert a == b, message: "Assert failed\n\n#{a}\n\nis not equal to\n\n#{b}"
    end
  end

  def type(field), do: OpenApi.type(field)
  def model(field), do: OpenApi.model("t", field)
  def encode(field), do: OpenApi.encode(field, Macro.var(:x, Tesla.OpenApi))
  def decode(field), do: OpenApi.decode(field, Macro.var(:x, Tesla.OpenApi))

  def operation(method, path, op, config \\ Config),
    do: OpenApi.operation(method, path, op, config)

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
    :erlang.put(:__tesla__caller, X)
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

      assert render(type(schema)) == "binary"
      assert render(type({"ref", schema})) == "X.ref()"

      assert render(model(schema)) == "@type t :: binary"

      assert render(encode(schema)) == "x"
      assert render(encode({"ref", schema})) == "x"

      assert render(decode(schema)) == "{:ok, x}"
      assert render(decode({"ref", schema})) == "{:ok, x}"
    end

    test "integer schema" do
      schema = %{"type" => "integer"}

      assert render(type(schema)) == "integer"
      assert render(type({"ref", schema})) == "X.ref()"

      assert render(model(schema)) == "@type t :: integer"

      assert render(encode(schema)) == "x"
      assert render(encode({"ref", schema})) == "x"

      assert render(decode(schema)) == "{:ok, x}"
      assert render(decode({"ref", schema})) == "{:ok, x}"
    end

    test "integer or null schema" do
      schema = %{"type" => ["integer", "null"]}

      assert render(type(schema)) == "integer | nil"
      assert render(model(schema)) == "@type t :: integer | nil"

      assert_quoted encode(schema) do
        cond do
          true ->
            x

          true ->
            x
        end
      end

      assert render(decode(schema)) == "{:ok, x}"
    end

    test "array of strings schema" do
      schema = %{"type" => "array", "items" => %{"type" => "string"}}

      assert render(type(schema)) == "list(binary)"
      assert render(type({"ref", schema})) == "X.Ref.t()"

      assert_quoted model(schema) do
        defmodule T do
          @moduledoc ""
          @type t :: list(binary)
          def decode(data) do
            Tesla.OpenApi.decode_list(data, fn data -> {:ok, data} end)
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
        Tesla.OpenApi.decode_list(x, fn data -> {:ok, data} end)
      end

      assert_quoted decode({"ref", schema}) do
        X.Ref.decode(x)
      end
    end

    test "unknown array schema" do
      schema = %{"type" => "array"}

      assert render(type(schema)) == "list"
      assert render(type({"ref", schema})) == "X.Ref.t()"

      assert_quoted model(schema) do
        defmodule T do
          @moduledoc ""
          @type t :: list
          def decode(data), do: {:ok, data}
          def encode(data), do: data
        end
      end

      assert render(encode(schema)) == "x"
      assert render(encode({"ref", schema})) == "X.Ref.encode(x)"

      assert_quoted decode(schema) do
        {:ok, x}
      end

      assert_quoted decode({"ref", schema}) do
        X.Ref.decode(x)
      end
    end

    test "unknown items schema" do
      schema = %{"items" => %{"type" => "object"}}

      assert render(type(schema)) == "list(map())"

      assert render(encode(schema)) == "x"

      assert_quoted decode(schema) do
        Tesla.OpenApi.decode_list(x, fn data -> {:ok, data} end)
      end
    end

    test "oneof items with schemas" do
      schema = %{"items" => [%{"type" => "integer"}, %{"type" => "string"}]}

      assert render(type(schema)) == "integer | binary"

      assert_quoted model(schema) do
        defmodule T do
          @moduledoc ""
          @type t :: integer | binary
          def decode(data) do
            cond do
              true ->
                {:ok, data}

              true ->
                {:ok, data}
            end
          end

          def encode(data) do
            cond do
              true ->
                data

              true ->
                data
            end
          end
        end
      end

      assert_quoted encode(schema) do
        cond do
          true ->
            x

          true ->
            x
        end
      end

      assert_quoted decode(schema) do
        cond do
          true ->
            {:ok, x}

          true ->
            {:ok, x}
        end
      end
    end

    test "anyof inline objects, lists and primitives" do
      schema = %{
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
              "id" => %{"type" => "integer"},
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
      }

      assert_quoted type(schema) do
        %{full_name: binary, id: integer, name: binary} | list(integer | binary) | binary
      end

      assert_quoted encode(schema) do
        cond do
          is_map(x) ->
            %{
              "fullName" => x.full_name,
              "id" =>
                cond do
                  true -> x.id
                  true -> x.id
                end,
              "name" => x.name
            }

          is_list(x) ->
            Tesla.OpenApi.encode_list(x, fn item ->
              cond do
                true -> item
                true -> item
              end
            end)

          true ->
            x
        end
      end

      assert_quoted decode(schema) do
        cond do
          is_map(x) ->
            with(
              {:ok, full_name} <- {:ok, x["fullName"]},
              {:ok, id} <-
                cond do
                  true ->
                    {:ok, x["id"]}

                  true ->
                    {:ok, x["id"]}
                end,
              {:ok, name} <- {:ok, x["name"]}
            ) do
              {:ok, %{full_name: full_name, id: id, name: name}}
            end

          is_list(x) ->
            Tesla.OpenApi.decode_list(x, fn data ->
              cond do
                true ->
                  {:ok, data}

                true ->
                  {:ok, data}
              end
            end)

          true ->
            {:ok, x}
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

      assert render(type(schema)) == "%{id: integer, name: binary}"
      assert render(type({"ref", schema})) == "X.Ref.t()"

      assert_quoted model(schema) do
        defmodule T do
          @moduledoc ""
          defstruct id: nil, name: nil
          @type t :: %__MODULE__{id: integer, name: binary}
          def decode(data) do
            with {:ok, id} <- {:ok, data["id"]},
                 {:ok, name} <- {:ok, data["name"]} do
              {:ok, %__MODULE__{id: id, name: name}}
            end
          end

          def encode(data) do
            %{"id" => data.id, "name" => data.name}
          end
        end
      end
    end

    test "object with references" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "integer"},
          "user" => %{"$ref" => "#/definitions/User"}
        }
      }

      spec = %{
        "definitions" => %{
          "User" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{
                "type" => "string"
              }
            }
          }
        }
      }

      :erlang.put(:__tesla__spec, spec)

      assert render(type(schema)) == "%{id: integer, user: X.User.t()}"

      assert_quoted decode(schema) do
        with {:ok, id} <- {:ok, x["id"]},
             {:ok, user} <- X.User.decode(x["user"]) do
          {:ok, %{id: id, user: user}}
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

      assert render(type(schema)) == "%{id: integer, name: binary}"
      assert render(type({"ref", schema})) == "X.Ref.t()"

      assert_quoted model(schema) do
        defmodule T do
          @moduledoc ""
          defstruct id: nil, name: nil
          @type t :: %__MODULE__{id: integer, name: binary}
          def decode(data) do
            with {:ok, id} <- {:ok, data["id"]},
                 {:ok, name} <- {:ok, data["name"]} do
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

      :erlang.put(:__tesla__spec, spec)

      assert_quoted operation("get", "/two/{id}", op) do
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

    test "request body" do
      op = %{
        "operationId" => "one",
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
        "responses" => []
      }

      assert_quoted operation("post", "/", op) do
        @doc ""
        @spec one(Tesla.Client.t(), integer) :: {:error, any}
        def one(client \\ new(), body) do
          case Tesla.post(client, "/", body) do
            {:error, error} -> {:error, error}
          end
        end

        defoverridable(one: 2)
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

  describe "Optimization" do
    import Tesla.OpenApi, only: [optimize: 1]

    test "remove unnecessary with clauses" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "integer"},
          "user" => %{"$ref" => "#/definitions/User"}
        }
      }

      spec = %{
        "definitions" => %{
          "User" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{
                "type" => "string"
              }
            }
          }
        }
      }

      :erlang.put(:__tesla__spec, spec)

      assert_quoted optimize(decode(schema)) do
        with {:ok, user} <- X.User.decode(x["user"]) do
          {:ok, %{id: x["id"], user: user}}
        end
      end
    end

    test "remove empty with" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "integer"},
          "name" => %{"type" => "string"}
        }
      }

      # before
      assert_quoted decode(schema) do
        with {:ok, id} <- {:ok, x["id"]},
             {:ok, name} <- {:ok, x["name"]} do
          {:ok, %{id: id, name: name}}
        end
      end

      # after
      assert_quoted optimize(decode(schema)) do
        {:ok, %{id: x["id"], name: x["name"]}}
      end
    end

    test "remove unnecesary encode_list / decode_list" do
      schema = %{"type" => "array", "items" => %{"type" => "string"}}

      # before
      assert_quoted decode(schema) do
        Tesla.OpenApi.decode_list(x, fn data -> {:ok, data} end)
      end

      assert_quoted encode(schema) do
        Tesla.OpenApi.encode_list(x, fn item -> item end)
      end

      # after
      assert_quoted optimize(decode(schema)) do
        {:ok, x}
      end

      assert_quoted optimize(encode(schema)) do
        x
      end
    end

    test "remove unnecessary conds" do
      schema = %{
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
              "id" => %{"type" => "integer"},
              "fullName" => %{"type" => "string"}
            }
          },
          %{
            "type" => "array",
            "items" => %{"type" => "string"}
          },
          %{
            "type" => "array",
            "items" => %{"type" => "integer"}
          },
          %{
            "type" => "string"
          },
          %{
            "type" => "integer"
          }
        ]
      }

      assert_quoted optimize(encode(schema)) do
        cond do
          is_map(x) -> %{"fullName" => x.full_name, "id" => x.id, "name" => x.name}
          is_list(x) -> x
          true -> x
        end
      end

      assert_quoted optimize(decode(schema)) do
        cond do
          is_map(x) ->
            {:ok, %{full_name: x["fullName"], id: x["id"], name: x["name"]}}

          is_list(x) ->
            {:ok, x}

          true ->
            {:ok, x}
        end
      end
    end
  end
end
