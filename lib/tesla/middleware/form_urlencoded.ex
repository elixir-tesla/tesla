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

  @content_type "application/x-www-form-urlencoded"

  def call(env, next, _opts) do
    env
    |> encode()
    |> Tesla.run(next)
    |> case do
      {:ok, env} -> {:ok, decode(env)}
      error -> error
    end
  end

  defp encode(env) do
    if encodable?(env) do
      env
      |> Map.update!(:body, &encode_body(&1))
      |> Tesla.put_headers([{"content-type", @content_type}])
    else
      env
    end
  end

  defp encodable?(%{body: nil}), do: false
  defp encodable?(%{body: %Tesla.Multipart{}}), do: false
  defp encodable?(_), do: true

  defp encode_body(body) when is_binary(body), do: body
  defp encode_body(body), do: do_encode(body)

  defp decode(env) do
    if decodable?(env) do
      env
      |> Map.update!(:body, &decode_body(&1))
    else
      env
    end
  end

  defp decodable?(env), do: decodable_body?(env) && decodable_content_type?(env)

  defp decodable_body?(env) do
    (is_binary(env.body) && env.body != "") || (is_list(env.body) && env.body != [])
  end

  defp decodable_content_type?(env) do
    case Tesla.get_header(env, "content-type") do
      nil -> false
      content_type -> String.starts_with?(content_type, @content_type)
    end
  end

  defp decode_body(body), do: do_decode(body)

  defp do_encode(data), do: URI.encode_query(data)
  defp do_decode(data), do: URI.decode_query(data)
end
