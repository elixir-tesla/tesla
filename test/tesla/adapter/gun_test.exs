defmodule Tesla.Adapter.GunTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Gun
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.SSL

  test "timeout option" do
    request = %Env{
      method: :get,
      url: "#{@http}/delay/2"
    }

    assert {:error, "read response timeout"} = Tesla.Adapter.Gun.call(request, timeout: 1_000)
  end

  test "max_body option" do
    request = %Env{
      method: :get,
      url: "#{@http}/get",
      query: [
        message: "Hello world!"
      ]
    }

    assert {:error, "body too large"} = Tesla.Adapter.Gun.call(request, max_body: 5)
  end
end
