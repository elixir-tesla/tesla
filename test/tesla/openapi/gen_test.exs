defmodule Tesla.OpenApi.GenTest do
  use ExUnit.Case

  import Tesla.OpenApiTest.Helpers

  alias Tesla.OpenApi3.{Prim, Union, Array, Object, Ref, Any}
  alias Tesla.OpenApi3.Model
  import Tesla.OpenApi3.Gen
  import Tesla.OpenApi3.Clean, only: [clean: 1]
  import Tesla.OpenApi3.Spec, only: [load: 1]

  @var Macro.var(:var, __MODULE__)

  setup do
    :erlang.put(:__tesla__caller, Petstore)
    :ok
  end

  describe "type/1" do
    test "binary" do
      assert_code type(%Prim{type: :binary}) do
        binary
      end
    end

    test "number" do
      assert_code type(%Prim{type: :number}) do
        number
      end
    end

    test "union of two" do
      assert_code type(%Union{
                    of: [
                      %Prim{type: :binary},
                      %Prim{type: :number}
                    ]
                  }) do
        binary | number
      end
    end

    test "union of three" do
      assert_code type(%Union{
                    of: [
                      %Prim{type: :binary},
                      %Prim{type: :boolean},
                      %Prim{type: :number}
                    ]
                  }) do
        binary | boolean | number
      end
    end

    test "union of union" do
      assert_code type(%Union{
                    of: [
                      %Union{
                        of: [
                          %Prim{type: :binary},
                          %Prim{type: :number}
                        ]
                      },
                      %Prim{type: :boolean},
                      %Prim{type: :number}
                    ]
                  }) do
        binary | number | boolean
      end
    end

    test "array of any" do
      assert_code type(%Array{of: %Any{}}) do
        list
      end
    end

    test "array of integer" do
      assert_code type(%Array{of: %Prim{type: :integer}}) do
        list(integer)
      end
    end

    test "array of union" do
      assert_code type(%Array{
                    of: %Union{
                      of: [
                        %Prim{type: :binary},
                        %Prim{type: :number}
                      ]
                    }
                  }) do
        list(binary | number)
      end
    end

    test "object empty" do
      assert_code type(%Object{props: %{}}) do
        %{}
      end
    end

    test "object with properties" do
      assert_code type(%Object{
                    props: %{
                      "id" => %Prim{type: :integer},
                      "nameOf" => %Prim{type: :binary}
                    }
                  }) do
        %{id: integer, name_of: binary}
      end
    end

    test "ref" do
      load(%{"" => %{"type" => "object"}})

      assert_code type(%Ref{name: "Pet", ref: "#/"}) do
        Petstore.Pet.t()
      end
    end

    test "any" do
      assert_code type(%Any{}) do
        any
      end
    end
  end

  describe "encode/2" do
    test "binary" do
      assert_code encode(%Prim{type: :binary}, @var) do
        var
      end
    end

    test "number" do
      assert_code encode(%Prim{type: :number}, @var) do
        var
      end
    end

    test "union of two" do
      schema = %Union{
        of: [
          %Prim{type: :binary},
          %Prim{type: :number}
        ]
      }

      assert_code encode(schema, @var) do
        cond do
          true -> var
          true -> var
        end
      end

      assert_code clean(encode(schema, @var)) do
        var
      end
    end

    test "union of three" do
      schema = %Union{
        of: [
          %Prim{type: :binary},
          %Prim{type: :boolean},
          %Prim{type: :number}
        ]
      }

      assert_code encode(schema, @var) do
        cond do
          true -> var
          true -> var
          true -> var
        end
      end

      assert_code clean(encode(schema, @var)) do
        var
      end
    end

    test "union of array & object of union" do
      schema = %Union{
        of: [
          %Array{
            of: %Union{
              of: [
                %Prim{type: :binary},
                %Prim{type: :number}
              ]
            }
          },
          %Object{
            props: %{
              "id" => %Prim{type: :integer}
            }
          },
          %Prim{type: :boolean}
        ]
      }

      assert_code encode(schema, @var) do
        cond do
          is_list(var) ->
            Tesla.OpenApi.encode_list(var, fn item ->
              cond do
                true ->
                  item

                true ->
                  item
              end
            end)

          is_map(var) ->
            %{"id" => var.id}

          true ->
            var
        end
      end

      assert_code clean(encode(schema, @var)) do
        cond do
          is_list(var) -> var
          is_map(var) -> %{"id" => var.id}
          true -> var
        end
      end
    end

    test "array of any" do
      schema = %Array{of: %Any{}}

      assert_code encode(schema, @var) do
        Tesla.OpenApi.encode_list(var, fn item -> item end)
      end

      assert_code clean(encode(schema, @var)) do
        var
      end
    end

    test "array of integer" do
      schema = %Array{of: %Prim{type: :integer}}

      assert_code encode(schema, @var) do
        Tesla.OpenApi.encode_list(var, fn item -> item end)
      end

      assert_code clean(encode(schema, @var)) do
        var
      end
    end

    test "array of refs" do
      load(%{"" => %{"type" => "object"}})
      schema = %Array{of: %Ref{ref: "#/", name: "Pet"}}

      assert_code encode(schema, @var) do
        Tesla.OpenApi.encode_list(var, fn item -> Petstore.Pet.encode(item) end)
      end

      assert_code clean(encode(schema, @var)) do
        Tesla.OpenApi.encode_list(var, fn item -> Petstore.Pet.encode(item) end)
      end
    end

    test "object empty" do
      schema = %Object{props: %{}}

      assert_code encode(schema, @var) do
        %{}
      end

      assert_code clean(encode(schema, @var)) do
        %{}
      end
    end

    test "object with properties" do
      schema = %Object{
        props: %{
          "id" => %Prim{type: :integer},
          "nameOf" => %Prim{type: :binary}
        }
      }

      assert_code encode(schema, @var) do
        %{"id" => var.id, "nameOf" => var.name_of}
      end

      assert_code clean(encode(schema, @var)) do
        %{"id" => var.id, "nameOf" => var.name_of}
      end
    end

    test "ref" do
      load(%{"" => %{"type" => "object"}})
      schema = %Ref{name: "Pet", ref: "#/"}

      assert_code encode(schema, @var) do
        Petstore.Pet.encode(var)
      end
    end

    test "any" do
      assert_code encode(%Any{}, @var) do
        var
      end
    end
  end

  describe "decode/2" do
    test "binary" do
      assert_code decode(%Prim{type: :binary}, @var) do
        {:ok, var}
      end
    end

    test "number" do
      assert_code decode(%Prim{type: :number}, @var) do
        {:ok, var}
      end
    end

    test "union of two" do
      schema = %Union{
        of: [
          %Prim{type: :binary},
          %Prim{type: :number}
        ]
      }

      assert_code decode(schema, @var) do
        cond do
          true -> {:ok, var}
          true -> {:ok, var}
        end
      end

      assert_code clean(decode(schema, @var)) do
        {:ok, var}
      end
    end

    test "union of three" do
      schema = %Union{
        of: [
          %Prim{type: :binary},
          %Prim{type: :boolean},
          %Prim{type: :number}
        ]
      }

      assert_code decode(schema, @var) do
        cond do
          true -> {:ok, var}
          true -> {:ok, var}
          true -> {:ok, var}
        end
      end

      assert_code clean(decode(schema, @var)) do
        {:ok, var}
      end
    end

    test "union of array & object of union" do
      schema = %Union{
        of: [
          %Array{
            of: %Union{
              of: [
                %Prim{type: :binary},
                %Prim{type: :number}
              ]
            }
          },
          %Object{
            props: %{
              "id" => %Prim{type: :integer}
            }
          },
          %Prim{type: :boolean}
        ]
      }

      assert_code decode(schema, @var) do
        cond do
          is_list(var) ->
            Tesla.OpenApi.decode_list(var, fn item ->
              cond do
                true -> {:ok, item}
                true -> {:ok, item}
              end
            end)

          is_map(var) ->
            with({:ok, id} <- {:ok, var["id"]}) do
              {:ok, %{id: id}}
            end

          true ->
            {:ok, var}
        end
      end

      assert_code clean(decode(schema, @var)) do
        cond do
          is_list(var) -> {:ok, var}
          is_map(var) -> {:ok, %{id: var["id"]}}
          true -> {:ok, var}
        end
      end
    end

    test "array of any" do
      schema = %Array{of: %Any{}}

      assert_code decode(schema, @var) do
        Tesla.OpenApi.decode_list(var, fn item -> {:ok, item} end)
      end

      assert_code clean(decode(schema, @var)) do
        {:ok, var}
      end
    end

    test "array of integer" do
      schema = %Array{of: %Prim{type: :integer}}

      assert_code decode(schema, @var) do
        Tesla.OpenApi.decode_list(var, fn item -> {:ok, item} end)
      end

      assert_code clean(decode(schema, @var)) do
        {:ok, var}
      end
    end

    test "object empty" do
      schema = %Object{props: %{}}

      assert_code decode(schema, @var) do
        with do
          {:ok, %{}}
        end
      end

      assert_code clean(decode(schema, @var)) do
        {:ok, %{}}
      end
    end

    test "object with properties" do
      schema = %Object{
        props: %{
          "id" => %Prim{type: :integer},
          "nameOf" => %Prim{type: :binary}
        }
      }

      assert_code decode(schema, @var) do
        with({:ok, id} <- {:ok, var["id"]}, {:ok, name_of} <- {:ok, var["nameOf"]}) do
          {:ok, %{id: id, name_of: name_of}}
        end
      end

      assert_code clean(decode(schema, @var)) do
        {:ok, %{id: var["id"], name_of: var["nameOf"]}}
      end
    end

    test "ref" do
      load(%{"" => %{"type" => "object"}})
      schema = %Ref{name: "Pet", ref: "#/"}

      assert_code decode(schema, @var) do
        Petstore.Pet.decode(var)
      end
    end

    test "any" do
      assert_code decode(%Any{}, @var) do
        {:ok, var}
      end
    end
  end

  describe "model/1" do
    test "binary" do
      model = %Model{name: "name", schema: %Prim{type: :binary}}

      assert_code model(model) do
        @type name :: binary
      end

      # make sure ref to moduleless schema is inlined
      ref = %Ref{name: "name", ref: "#/"}
      load(%{"" => %{"type" => "string"}})

      assert_code type(ref) do
        name
      end

      assert_code encode(ref, @var) do
        var
      end

      assert_code decode(ref, @var) do
        {:ok, var}
      end
    end

    test "integer" do
      model = %Model{name: "name", schema: %Prim{type: :integer}}

      assert_code model(model) do
        @type name :: integer
      end
    end

    test "array of any" do
      model = %Model{name: "name", schema: %Array{of: %Any{}}}

      assert_code model(model) do
        @type name :: list
      end
    end

    test "array of string" do
      model = %Model{name: "name", schema: %Array{of: %Prim{type: :binary}}}

      assert_code model(model) do
        defmodule Name do
          # @moduledoc ""
          @type t :: list(binary)
          def encode(data) do
            Tesla.OpenApi.encode_list(data, fn item -> item end)
          end

          def decode(data) do
            Tesla.OpenApi.decode_list(data, fn item -> {:ok, item} end)
          end
        end
      end

      assert_code clean(model(model)) do
        defmodule Name do
          # @moduledoc ""
          @type t :: list(binary)
          def encode(data), do: data
          def decode(data), do: {:ok, data}
        end
      end
    end

    test "union of string and int" do
      model = %Model{
        name: "name",
        schema: %Union{
          of: [
            %Prim{type: :binary},
            %Prim{type: :integer}
          ]
        }
      }

      assert_code model(model) do
        defmodule Name do
          # @moduledoc ""
          @type t :: binary | integer
          def encode(data) do
            cond do
              true -> data
              true -> data
            end
          end

          def decode(data) do
            cond do
              true -> {:ok, data}
              true -> {:ok, data}
            end
          end
        end
      end

      assert_code clean(model(model)) do
        defmodule Name do
          # @moduledoc ""
          @type t :: binary | integer
          def encode(data), do: data
          def decode(data), do: {:ok, data}
        end
      end
    end

    test "object with properties" do
      model = %Model{
        name: "name",
        schema: %Object{
          props: %{
            "id" => %Prim{type: :integer},
            "nameOf" => %Prim{type: :binary}
          }
        }
      }

      assert_code model(model) do
        defmodule Name do
          # @moduledoc ""
          defstruct id: nil, name_of: nil
          @type t :: %__MODULE__{id: integer, name_of: binary}
          def encode(data) do
            %{"id" => data.id, "nameOf" => data.name_of}
          end

          def decode(data) do
            with {:ok, id} <- {:ok, data["id"]},
                 {:ok, name_of} <- {:ok, data["nameOf"]} do
              {:ok, %__MODULE__{id: id, name_of: name_of}}
            end
          end
        end
      end

      assert_code clean(model(model)) do
        defmodule Name do
          # @moduledoc ""
          defstruct id: nil, name_of: nil
          @type t :: %__MODULE__{id: integer, name_of: binary}
          def encode(data) do
            %{"id" => data.id, "nameOf" => data.name_of}
          end

          def decode(data) do
            {:ok, %__MODULE__{id: data["id"], name_of: data["nameOf"]}}
          end
        end
      end
    end
  end
end
