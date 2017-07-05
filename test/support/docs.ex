defmodule TeslaDocsTest do
  defmodule Default do
    use Tesla
  end

  defmodule NoDocs do
    use Tesla, docs: false

    @doc """
    Something something
    """
    def custom(url), do: get(url)
  end

  defmodule Doctest do
    @moduledoc """
    iex> 1 + 1
    2
    """
    use Tesla

    @doc """
    iex> 2 + 2
    4
    """
    def custom(url), do: get(url)
  end
end
