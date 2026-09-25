defmodule Tesla.Middleware.Headers do
  @moduledoc ~S"""
  Set default headers for all requests

  ## Examples

  ```elixir
  defmodule Myclient do
    def client do
      Tesla.client([
        {Tesla.Middleware.Headers, [{"user-agent", "Tesla"}]}
      ])
    end
  end
  ```

  ## Secret header values

  Header values given here are stored in the client, so wrap sensitive ones
  in `Tesla.SecretString` to keep them out of `inspect/1` output. The value
  is unwrapped when it is put on the request.

  ```elixir
  Tesla.client([
    {Tesla.Middleware.Headers, [{"authorization", Tesla.SecretString.new("Bearer #{token}")}]}
  ])
  ```
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, headers) do
    env
    |> Tesla.put_headers(Enum.map(headers, &reveal/1))
    |> Tesla.run(next)
  end

  defp reveal({name, %Tesla.SecretString{} = value}), do: {name, to_string(value)}
  defp reveal(header), do: header
end
