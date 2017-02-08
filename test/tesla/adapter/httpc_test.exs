defmodule HttpcTest do
  use ExUnit.Case
  use Tesla.Adapter.TestCase.Basic, adapter: :httpc
  use Tesla.Adapter.TestCase.StreamRequestBody, adapter: :httpc
  use Tesla.Adapter.TestCase.SSL, adapter: :httpc
end
