defmodule Tesla.Adapter.HackneyTest do
  use ExUnit.Case
  use Tesla.Adapter.TestCase.Basic, adapter: :hackney
  use Tesla.Adapter.TestCase.StreamRequestBody, adapter: :hackney
  use Tesla.Adapter.TestCase.SSL, adapter: :hackney
end
