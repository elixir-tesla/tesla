defmodule Tesla.Middleware.FormUrlencoded do
  @doc """
  Send request body as application/x-www-form-urlencoded

  Example:
      defmodule Myclient do
        use Tesla

        plug Tesla.Middleware.FormUrlencoded
      end

      Myclient.post("/url", %{key: :value})
  """
  def call(env, next, opts) do
    opts = opts || []

    env
    |> encode(opts)
    |> Tesla.run(next)
  end

  def encode(env, opts) do
    if encodable?(env) do
      env
      |> Map.update!(:body, &encode_body(&1, opts))
      |> Tesla.Middleware.Headers.call([], %{"content-type" => "application/x-www-form-urlencoded"})
    else
      env
    end
  end

  defp encode_body(body, _opts) when is_binary(body), do: body

  defp encode_body(body, _opts), do: do_process(body)

  def encodable?(env), do: env.body != nil

  defp do_process(data) do
    URI.encode_query(data)
  end
end
