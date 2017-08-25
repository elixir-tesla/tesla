defmodule Tesla.Adapter.IbrowseTest do
  use ExUnit.Case
  use Tesla.Adapter.TestCase.Basic, adapter: :ibrowse
  use Tesla.Adapter.TestCase.StreamRequestBody, adapter: :ibrowse
  use Tesla.Adapter.TestCase.SSL, adapter: :ibrowse
end
