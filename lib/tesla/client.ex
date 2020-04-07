defmodule Tesla.Client do
  @type adapter :: module | {module, any} | (Tesla.Env.t() -> Tesla.Env.result())
  @type middleware :: module | {module, any}

  @type t :: %__MODULE__{
          pre: Tesla.Env.stack(),
          post: Tesla.Env.stack(),
          adapter: adapter | nil
        }
  defstruct fun: nil,
            pre: [],
            post: [],
            adapter: nil
end
