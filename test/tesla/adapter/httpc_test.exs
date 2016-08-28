defmodule HttpcTest do
  use ExUnit.Case
  use Tesla.Adapter.TestCase.Basic, adapter: :httpc
end
