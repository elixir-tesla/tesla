defmodule IbrowseTest do
  use ExUnit.Case
  use Tesla.Adapter.TestCase.Basic, adapter: Tesla.Adapter.Ibrowse

  setup do
    Application.ensure_started(:ibrowse)
    :ok
  end
end
