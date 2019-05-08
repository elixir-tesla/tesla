defmodule Tesla.Adapter.MintTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Mint
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.SSL
end
