defmodule Tesla.Middleware.BasicAuth do
  @moduledoc """
  Basic authentication middleware.

  [Wiki on the topic](https://en.wikipedia.org/wiki/Basic_access_authentication)

  ## Example

  ```
  defmodule MyClient do
    use Tesla

    # static configuration
    plug Tesla.Middleware.BasicAuth, username: "user", password: "pass"

    # dynamic user & pass
    def new(username, password, opts \\\\ %{}) do
      Tesla.client [
        {Tesla.Middleware.BasicAuth, Map.merge(%{username: username, password: password}, opts)}
      ]
    end
  end
  ```

  ## Options

  - `:username` - username (defaults to `""`)
  - `:password` - password (defaults to `""`)
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    opts = opts || %{}

    env
    |> Tesla.put_headers(authorization_header(opts))
    |> Tesla.run(next)
  end

  defp authorization_header(opts) do
    opts
    |> authorization_vars()
    |> encode()
    |> create_header()
  end

  defp authorization_vars(opts) do
    %{
      username: opts[:username] || "",
      password: opts[:password] || ""
    }
  end

  defp create_header(auth) do
    [{"authorization", "Basic #{auth}"}]
  end

  defp encode(%{username: username, password: password}) do
    Base.encode64("#{username}:#{password}")
  end
end
