defmodule Tesla.OpenApi3 do
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
    @type t :: %__MODULE__{of: Tesla.OpenApi3.schema()}
  end

  defmodule Object do
    defstruct props: %{}
    @type t :: %__MODULE__{props: %{binary => Tesla.OpenApi3.schema()}}
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
    @type t :: %__MODULE__{name: binary, schema: Tesla.OpenApi3.schema()}
  end

  defmodule Param do
    @enforce_keys [:name, :schema]
    defstruct name: nil, schema: nil
    @type t :: %__MODULE__{name: binary, schema: Tesla.OpenApi3.schema()}
  end

  defmodule Response do
    @enforce_keys [:code, :schema]
    defstruct code: nil, schema: nil
    @type t :: %__MODULE__{code: integer | :default, schema: Tesla.OpenApi3.schema()}
  end

  defmodule Operation do
    defstruct id: nil,
              path: nil,
              method: nil,
              path_params: [],
              query_params: [],
              body_params: [],
              request_body: nil,
              responses: []

    @type t :: %__MODULE__{
            id: binary,
            path: binary,
            method: binary,
            path_params: [Param.t()],
            query_params: [Param.t()],
            body_params: [Param.t()],
            request_body: Tesla.OpenApi3.schema() | nil,
            responses: [Response.t()]
          }
  end
end
