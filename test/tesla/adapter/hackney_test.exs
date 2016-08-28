defmodule HackneyTest do
  use ExUnit.Case
  use Tesla.Adapter.TestCase.Basic, adapter: Tesla.Adapter.Hackney
  use Tesla.Adapter.TestCase.StreamRequestBody, adapter: Tesla.Adapter.Hackney

  setup do
    case Application.ensure_started(:hackney) do
      {:error, _} -> :hackney.start
      :ok         -> :ok
    end
  end
end
