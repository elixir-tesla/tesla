defmodule Tesla.Adapter.HttpcTest do
  use ExUnit.Case
  use Tesla.AdapterCase.Basic, adapter: :httpc
  use Tesla.AdapterCase.StreamRequestBody, adapter: :httpc
  use Tesla.AdapterCase.SSL, adapter: :httpc
end
