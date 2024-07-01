defmodule Tesla.Middleware.BasicAuth do
  @moduledoc ~S"""
  Basic authentication middleware.

  [Wiki on the topic](https://en.wikipedia.org/wiki/Basic_access_authentication)

  ## Examples

  ```elixir
  defmodule MyClient do
    use Tesla

    # static configuration
    plug Tesla.Middleware.BasicAuth, Tesla.Middleware.BasicAuth.Options.new!(username: "user", password: "pass")

    # dynamic user & pass
    def new(username, password, opts \\ %{}) do
      Tesla.client [
        {Tesla.Middleware.BasicAuth, Tesla.Middleware.BasicAuth.Options.new!(Map.merge(%{username: username, password: password}, opts))}
      ]
    end
  end
  ```

  ## Options

  Visit `t:Tesla.Middleware.BasicAuth.Options.t/0` to read more about the options.

  > ### Using Map or Keyword List as Options {: .warning}
  >
  > It is possible to use `Map` or `Keyword` list as options, it is not recommended for security reasons.
  > The `inspect/2` implementation of `Tesla.Middleware.BasicAuth.Options` will redact the `username` and `password`
  > fields when you inspect the client.
  """

  @behaviour Tesla.Middleware

  defmodule Options do
    @moduledoc """
    Options for `Tesla.Middleware.BasicAuth`.
    """

    @typedoc """
    - `:username` - username (defaults to `""`)
    - `:password` - password (defaults to `""`)
    """
    @type t :: %__MODULE__{username: String.t(), password: String.t()}

    @derive {Inspect, except: [:username, :password]}
    defstruct username: "", password: ""

    @doc """
    Creates new `t:t/0` struct.
    """
    @spec new!(%__MODULE__{} | Keyword.t() | map) :: t()
    def new!(%__MODULE__{} = opts) do
      opts
    end

    def new!(attrs) do
      attrs = Map.merge(%{username: "", password: ""}, Enum.into(attrs, %{}))
      struct!(__MODULE__, attrs)
    end
  end

  @impl Tesla.Middleware
  def call(env, next, opts) do
    opts = Options.new!(opts)

    env
    |> Tesla.put_headers(authorization_header(opts))
    |> Tesla.run(next)
  end

  defp authorization_header(opts) do
    opts
    |> encode()
    |> create_header()
  end

  defp create_header(auth) do
    [{"authorization", "Basic #{auth}"}]
  end

  defp encode(%Options{} = opts) do
    Base.encode64("#{opts.username}:#{opts.password}")
  end
end
