defmodule Tesla.Adapter.MintTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Mint
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.SSL

  test "Delay request" do
    request = %Env{
      method: :head,
      url: "#{@http}/delay/1"
    }

    assert {:error, "Response timeout"} = call(request, adapter: [timeout: 100])
  end
end
