defmodule Tesla.OpenAPI.Response do
  @moduledoc """
  Macro for defining generated-client response wrappers.

  Generated clients own their response module and can use this macro to get a
  small wrapper around `t:Tesla.Env.t/0`:

      defmodule MyApi.Response do
        use Tesla.OpenAPI.Response
      end
  """

  defmacro __using__(_opts) do
    quote do
      @moduledoc """
      HTTP response wrapper with status, headers, and typed body.

      The `ok` field is `true` for 2xx status codes (200-299), `false` for
      other status codes, and `nil` when the status is not set.
      """

      @type headers() :: Tesla.Env.headers()

      @typedoc """
      HTTP response wrapper with status, headers, and typed body.

      ## Fields

        * `:status` - response status.
        * `:ok` - `true` for 2xx status codes (200-299), `false` for other
          status codes, or `nil` when the status is not set.
        * `:headers` - response headers.
        * `:body` - typed response body.
      """
      @type t(body_type, header_type) :: %__MODULE__{
              status: Tesla.Env.status(),
              ok: boolean() | nil,
              headers: header_type,
              body: body_type
            }

      defstruct status: nil, ok: nil, headers: nil, body: nil

      @doc false
      @spec new(Tesla.Env.t(), body_type) :: t(body_type, headers()) when body_type: term()
      def new(%Tesla.Env{status: nil} = env, body) do
        %__MODULE__{
          status: env.status,
          ok: nil,
          headers: env.headers,
          body: body
        }
      end

      def new(%Tesla.Env{} = env, body) do
        %__MODULE__{
          status: env.status,
          ok: env.status >= 200 and env.status <= 299,
          headers: env.headers,
          body: body
        }
      end
    end
  end
end
