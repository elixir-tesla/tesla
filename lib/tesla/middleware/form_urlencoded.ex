defmodule Tesla.Middleware.FormUrlencoded do
  @behaviour Tesla.Middleware

  @moduledoc """
  Send request body as application/x-www-form-urlencoded

  Longer description, including e.g. additional dependencies.


  ### Example usage
  ```
  defmodule Myclient do
    use Tesla

    plug Tesla.Middleware.FormUrlencoded
  end

  Myclient.post("/url", %{key: :value})
  ```
  """

  def call(env, next, opts) do
    opts = opts || []

    env
    |> encode(opts)
    |> Tesla.run(next)
  end

  defp encode(env, opts) do
    if encodable?(env) do
      env
      |> Map.update!(:body, &encode_body(&1, opts))
      |> Tesla.put_headers([{"content-type", "application/x-www-form-urlencoded"}])
    else
      env
    end
  end

  defp encode_body(body, _opts) when is_binary(body), do: body

  defp encode_body(body, _opts), do: do_process(body)

  defp encodable?(%{body: nil}), do: false
  defp encodable?(%{body: %Tesla.Multipart{}}), do: false
  defp encodable?(_), do: true

  defp do_process(data) do
    URI.encode_query(data)
  end
end
