defmodule Tesla.Adapter.IbrowseTest do
  use ExUnit.Case
  use Tesla.AdapterCase.Basic, adapter: :ibrowse
  use Tesla.AdapterCase.StreamRequestBody, adapter: :ibrowse
  use Tesla.AdapterCase.SSL, adapter: :ibrowse
end
