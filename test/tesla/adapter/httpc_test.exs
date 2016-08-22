defmodule HttpcTest do
  use ExUnit.Case
  use Tesla.Adapter.TestCase.Basic, client: HttpcTest.Client

  defmodule Client do
    use Tesla.Builder

    adapter :httpc
  end
end
