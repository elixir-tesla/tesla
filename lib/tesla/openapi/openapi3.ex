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

  # defmodule Operation do
  #   defstruct []
  #   @type t :: %__MODULE__{}
  # end
end
