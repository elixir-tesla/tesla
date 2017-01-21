defmodule KatipoTest do
  use ExUnit.Case
  use Tesla.Adapter.TestCase.Basic, adapter: :katipo
  use Tesla.Adapter.TestCase.SSL, adapter: :katipo

  setup do
    Application.ensure_all_started(:katipo)
    :ok
  end
end
