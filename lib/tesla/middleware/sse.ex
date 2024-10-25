defmodule Tesla.Middleware.SSE do
  @moduledoc """
  Decode Server Sent Events.

  This middleware is mostly useful when streaming response body.

  ## Examples

  ```elixir
  defmodule MyClient do
    def client do
      Tesla.client([Tesla.Middleware.SSE, only: :data])
    end
  end
  ```

  ## Options

  - `:only` - keep only specified keys in event (necessary for using with `JSON` middleware)
  - `:decode_content_types` - list of additional decodable content-types
  """

  @behaviour Tesla.Middleware

  @default_content_types ["text/event-stream"]

  @impl Tesla.Middleware
  def call(env, next, opts) do
    opts = opts || []

    with {:ok, env} <- Tesla.run(env, next) do
      decode(env, opts)
    end
  end

  def decode(env, opts) do
    if decodable_content_type?(env, opts) do
      {:ok, %{env | body: decode_body(env.body, opts)}}
    else
      {:ok, env}
    end
  end

  defp decode_body(body, opts) when is_struct(body, Stream) or is_function(body) do
    body
    |> Stream.chunk_while(
      "",
      fn elem, acc ->
        {lines, [rest]} = (acc <> elem) |> String.split("\n\n") |> Enum.split(-1)
        {:cont, lines, rest}
      end,
      fn
        "" -> {:cont, ""}
        acc -> {:cont, acc, ""}
      end
    )
    |> Stream.flat_map(& &1)
    |> Stream.map(&decode_message/1)
    |> Stream.flat_map(&only(&1, opts[:only]))
  end

  defp decode_body(binary, opts) when is_binary(binary) do
    binary
    |> String.split("\n\n")
    |> Enum.map(&decode_message/1)
    |> Enum.flat_map(&only(&1, opts[:only]))
  end

  defp decode_message(message) do
    message
    |> String.split("\n")
    |> Enum.map(&decode_body/1)
    |> Enum.reduce(%{}, fn
      :empty, acc -> acc
      {:data, data}, acc -> Map.update(acc, :data, data, &(&1 <> "\n" <> data))
      {key, value}, acc -> Map.put_new(acc, key, value)
    end)
  end

  defp decode_body(": " <> comment), do: {:comment, comment}
  defp decode_body("data: " <> data), do: {:data, data}
  defp decode_body("event: " <> event), do: {:event, event}
  defp decode_body("id: " <> id), do: {:id, id}
  defp decode_body("retry: " <> retry), do: {:retry, retry}
  defp decode_body(""), do: :empty

  defp decodable_content_type?(env, opts) do
    case Tesla.get_header(env, "content-type") do
      nil -> false
      content_type -> Enum.any?(content_types(opts), &String.starts_with?(content_type, &1))
    end
  end

  defp content_types(opts),
    do: @default_content_types ++ Keyword.get(opts, :decode_content_types, [])

  defp only(message, nil), do: [message]

  defp only(message, key) do
    case Map.get(message, key) do
      nil -> []
      val -> [val]
    end
  end
end
