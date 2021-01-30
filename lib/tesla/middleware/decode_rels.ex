defmodule Tesla.Middleware.DecodeRels do
  @moduledoc """
  Decode `Link` Hypermedia HTTP header into `opts[:rels]` field in response.

  ## Examples

  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.DecodeRels
  end

  env = MyClient.get("/...")

  env.opts[:rels]
  # => %{"Next" => "http://...", "Prev" => "..."}
  ```
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, _opts) do
    env
    |> Tesla.run(next)
    |> parse_rels
  end

  defp parse_rels({:ok, env}), do: {:ok, parse_rels(env)}
  defp parse_rels({:error, reason}), do: {:error, reason}

  defp parse_rels(env) do
    if link = Tesla.get_header(env, "link") do
      Tesla.put_opt(env, :rels, rels(link))
    else
      env
    end
  end

  defp rels(link) do
    link
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&rel/1)
    |> Enum.into(%{})
  end

  defp rel(item) do
    Regex.run(~r/\A<(.+)>; rel=["]?([^"]+)["]?\z/, item, capture: :all_but_first)
    |> Enum.reverse()
    |> List.to_tuple()
  end
end
