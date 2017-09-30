defmodule Tesla.Adapter.IbrowseTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Ibrowse
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.SSL
end
