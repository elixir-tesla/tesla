defmodule IbrowseTest do
  use ExUnit.Case
  use Tesla.Adapter.TestCase.Basic, adapter: :ibrowse
  use Tesla.Adapter.TestCase.SSL, adapter: :ibrowse

  setup do
    Application.ensure_started(:ibrowse)
    :ok
  end
end
