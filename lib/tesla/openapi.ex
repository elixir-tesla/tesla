defmodule Tesla.OpenApi do
  defmodule Prim do
    @enforce_keys [:type]
    defstruct type: nil
    @type t :: %__MODULE__{type: :binary | :integer | :number | :boolean}
  end

  defmodule Union do
    @enforce_keys [:of]
    defstruct of: nil

    @type t :: %__MODULE__{
            of: [Tesla.OpenApi.Object.t() | Tesla.OpenApi.Array.t() | Tesla.OpenApi.Prim.t()]
          }
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
    defstruct name: nil, title: nil, description: nil, schema: nil

    @type t :: %__MODULE__{
            name: binary,
            title: binary | nil,
            description: binary | nil,
            schema: Tesla.OpenApi.schema()
          }
  end

  defmodule Param do
    @enforce_keys [:name, :schema]
    defstruct name: nil, description: nil, schema: nil

    @type t :: %__MODULE__{
            name: binary,
            description: binary | nil,
            schema: Tesla.OpenApi.schema()
          }
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
              external_docs: nil,
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
            external_docs: %{description: binary, url: binary} | nil,
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
  alias Tesla.OpenApi.Context

  defmacro __using__(opts) do
    {opts, _} = Code.eval_quoted(opts)
    generate(__CALLER__.module, opts)
  end

  def generate(module, opts) do
    raw =
      cond do
        file = opts[:spec] -> read_spec_from_file(file, opts)
        url = opts[:spec_url] -> read_spec_from_url(url, opts)
      end

    dump = Keyword.get(opts, :dump, false)

    Context.put_spec(raw)
    Context.put_caller(module)
    Context.put_config(config(opts))

    spec = Spec.new(raw)
    code = Gen.gen(spec)

    [
      if(opts[:spec], do: quote(do: @external_resource(unquote(opts[:spec])))),
      code
    ]
    |> dump(dump)
  end

  defp read_spec_from_file(file, opts) do
    read_spec(File.read!(file), opts)
  end

  defp read_spec_from_url(url, opts) do
    client = Tesla.client([], Tesla.Adapter.Httpc)
    {:ok, %{status: 200, body: body}} = Tesla.get(client, url)
    read_spec(body, opts)
  end

  defp read_spec(binary, opts) do
    merge(Jason.decode!(binary), opts[:extra])
  end

  defp merge(x, nil), do: x
  defp merge(%{} = x, %{} = y), do: Map.merge(x, y, fn _k, x, y -> merge(x, y) end)

  defp dump(code, false), do: code

  defp dump(code, file) do
    caller = Context.get_caller()

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

  def config(opts) do
    op_name =
      case opts[:operations][:name] do
        fun when is_function(fun) -> fun
        nil -> fn name -> name end
      end

    op_gen? =
      case opts[:operations][:only] do
        only when is_list(only) -> fn name -> name in only end
        nil -> fn _ -> true end
      end

    %{
      op_name: op_name,
      op_gen?: op_gen?
    }
  end

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
