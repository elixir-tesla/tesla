if Version.compare(System.version(), "1.5.0") != :lt do
  defmodule Tesla.Adapter.MintTest do
    use ExUnit.Case

    use Tesla.AdapterCase, adapter: Tesla.Adapter.Mint
    use Tesla.AdapterCase.Basic
    use Tesla.AdapterCase.Multipart
    use Tesla.AdapterCase.StreamRequestBody
    use Tesla.AdapterCase.SSL
  end
end
