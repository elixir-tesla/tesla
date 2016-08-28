defmodule IbrowseTest do
  use ExUnit.Case
  use Tesla.Adapter.TestCase.Basic, adapter: :ibrowse

  setup do
    Application.ensure_started(:ibrowse)
    :ok
  end
end
