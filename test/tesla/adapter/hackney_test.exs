defmodule HackneyTest do
  use ExUnit.Case
  use Tesla.Adapter.TestCase.Basic, adapter: :hackney
  use Tesla.Adapter.TestCase.StreamRequestBody, adapter: :hackney
  use Tesla.Adapter.TestCase.StreamResponseBody, adapter: :hackney

  setup do
    case Application.ensure_started(:hackney) do
      {:error, _} -> :hackney.start
      :ok         -> :ok
    end
  end
end
