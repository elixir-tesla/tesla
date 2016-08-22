defmodule HackneyTest do
  use ExUnit.Case
  use Tesla.Adapter.TestCase, client: HackneyTest.Client

  defmodule Client do
    use Tesla.Builder

    adapter :hackney
  end

  setup do
    case Application.ensure_started(:hackney) do
      {:error, _} -> :hackney.start
      :ok         -> :ok
    end    
  end
end
