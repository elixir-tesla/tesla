defmodule Tesla.Adapter.FinchTest do
  use ExUnit.Case

  @finch_name MyFinch

  use Tesla.AdapterCase, adapter: {Tesla.Adapter.Finch, [name: @finch_name]}
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  # use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.SSL

  setup do
    start_supervised!({Finch, name: @finch_name})
    :ok
  end
end
