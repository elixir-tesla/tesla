defmodule HttpcTest do
  use ExUnit.Case
  use Tesla.Adapter.TestCase.Basic, adapter: Tesla.Adapter.Httpc
end
