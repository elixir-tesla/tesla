defmodule TeslaDocsTest do
  defmodule Default do
    use Tesla
  end

  defmodule NoDocs do
    use Tesla, docs: false

    @doc """
    Something something.
    """
    def custom(url), do: get(url)
  end
end
