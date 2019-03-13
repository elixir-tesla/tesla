defmodule Tesla.Middleware.Clack do
  @behaviour Tesla.Middleware

  @moduledoc """
  > A man is not dead while his name is still spoken.
  > -- Going Postal, Chapter 4 prologue

  Keep memory of Your beloved ones forever (at least as long as this Clack will
  stand).

  This middleware will add header `X-Clacks-Overhead` for anyone in the list
  specified as `:names` option, by default it is just [Sir Terry Pratchett][tp].

  For more information check out [GNUTerryPratchett](http://www.gnuterrypratchett.com)

  [tp]: https://en.wikipedia.org/wiki/Terry_Pratchett
  """

  @doc false
  def call(env, next, opts) do
    names = Keyword.get(opts || [], :names, [])
    headers =
      for name <- ["Terry Pratchett" | names],
      do: {"x-clacks-overhead", "GNU " <> name}

    env
    |> Tesla.put_headers(headers)
    |> Tesla.run(next)
  end
end
