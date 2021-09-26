defmodule Tesla.OpenApi do
  defmodule Prim do
    @enforce_keys [:type]
    defstruct type: nil
    @type t :: %__MODULE__{type: :binary | :integer | :number | :boolean}
  end

  defmodule Union do
    @enforce_keys [:of]
    defstruct of: nil
    @type t :: %__MODULE__{of: [Object.t() | Array.t() | Prim.t()]}
  end

  defmodule Array do
    @enforce_keys [:of]
    defstruct of: nil
    @type t :: %__MODULE__{of: Tesla.OpenApi.schema()}
  end

  defmodule Object do
    defstruct props: %{}
    @type t :: %__MODULE__{props: %{binary => Tesla.OpenApi.schema()}}
  end

  defmodule Ref do
    @enforce_keys [:ref]
    defstruct ref: nil, name: nil
    @type t :: %__MODULE__{name: binary | nil, ref: binary}
  end

  defmodule Any do
    defstruct []
    @type t :: %__MODULE__{}
  end

  @type schema :: Prim.t() | Union.t() | Array.t() | Object.t() | Ref.t() | Any.t()

  defmodule Model do
    @enforce_keys [:name, :schema]
    defstruct name: nil, schema: nil
    @type t :: %__MODULE__{name: binary, schema: Tesla.OpenApi.schema()}
  end

  defmodule Param do
    @enforce_keys [:name, :schema]
    defstruct name: nil, schema: nil
    @type t :: %__MODULE__{name: binary, schema: Tesla.OpenApi.schema()}
  end

  defmodule Response do
    @enforce_keys [:code]
    defstruct code: nil, schema: nil
    @type t :: %__MODULE__{code: integer | :default, schema: Tesla.OpenApi.schema() | nil}
  end

  defmodule Operation do
    defstruct id: nil,
              summary: nil,
              description: nil,
              path: nil,
              method: nil,
              path_params: [],
              query_params: [],
              body_params: [],
              request_body: nil,
              responses: []

    @type t :: %__MODULE__{
            id: binary,
            summary: binary | nil,
            description: binary | nil,
            path: binary,
            method: binary,
            path_params: [Param.t()],
            query_params: [Param.t()],
            body_params: [Param.t()],
            request_body: Tesla.OpenApi.schema() | nil,
            responses: [Response.t()]
          }
  end

  alias Tesla.OpenApi.Spec
  alias Tesla.OpenApi.Gen

  defmacro __using__(opts \\ []) do
    file = Keyword.fetch!(opts, :spec)
    dump = Keyword.get(opts, :dump, false)

    # [{config, _}] = Code.compile_quoted(config(__CALLER__.module, opts))

    Spec.put_caller(__CALLER__.module)
    spec = Spec.read(file)
    code = Gen.gen(spec)

    quote do
      @external_resource unquote(file)
      unquote(code)
    end
    |> dump(dump)
  end

  defp dump(code, false), do: code

  defp dump(code, file) do
    caller = :erlang.get(:__tesla__caller)

    bin =
      quote do
        defmodule unquote(caller) do
          unquote(code)
        end
      end
      |> Macro.to_string()
      |> Code.format_string!()

    File.write!(file, bin)
    code
  end

  # [{config, _}] = Code.compile_quoted(config(__CALLER__.module, opts))

  # defp config(mod, opts) do
  #   op_name =
  #     case opts[:operations][:name] do
  #       nil -> quote(do: name)
  #       fun -> quote(do: unquote(fun).(name))
  #     end

  #   generate =
  #     case opts[:operations][:only] do
  #       only when is_list(only) -> quote(do: name in unquote(only))
  #       nil -> quote(do: name)
  #     end

  #   quote do
  #     defmodule unquote(:"#{mod}_config") do
  #       @moduledoc false
  #       def op_name(name), do: unquote(op_name)
  #       def generate?(name), do: unquote(generate)
  #     end
  #   end
  # end

  ## UTILITIES

  def encode_list(nil, _fun), do: nil
  def encode_list(list, fun), do: Enum.map(list, fun)

  def encode_query(query, keys) do
    Enum.reduce(keys, [], fn
      {key, format}, qs ->
        case query[key] do
          nil -> qs
          val -> Keyword.put(qs, key, encode_query_value(val, format))
        end
    end)
  end

  def decode_list(nil, _fun), do: {:ok, nil}
  def decode_list(list, _fun) when not is_list(list), do: {:ok, list}

  def decode_list(list, fun) do
    list
    |> Enum.reverse()
    |> Enum.reduce({:ok, []}, fn
      data, {:ok, items} ->
        with {:ok, item} <- fun.(data), do: {:ok, [item | items]}

      _, error ->
        error
    end)
  end

  defp encode_query_value(value, "csv"), do: Enum.join(value, ",")
  defp encode_query_value(value, "int32"), do: value
  defp encode_query_value(value, nil), do: value
end
