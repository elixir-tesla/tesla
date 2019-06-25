defmodule Tesla.Adapter.GunTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Gun
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.SSL

  test "fallback adapter timeout option" do
    request = %Env{
      method: :get,
      url: "#{@http}/delay/2"
    }

    assert {:error, :timeout} = Tesla.Adapter.Gun.call(request, timeout: 1_000)
  end

  test "max_body option" do
    request = %Env{
      method: :get,
      url: "#{@http}/get",
      query: [
        message: "Hello world!"
      ]
    }

    assert {:error, :body_too_large} = Tesla.Adapter.Gun.call(request, max_body: 5)
  end

  test "without slash" do
    request = %Env{
      method: :get,
      url: "#{@http}"
    }

    assert {:ok, %Env{} = response} = call(request)
    assert response.status == 400
  end

  test "response stream" do
    request = %Env{
      method: :get,
      url: "http://httpbin.org/stream/10"
    }

    assert {:ok, %Env{} = response} = call(request)
    assert response.status == 200
  end
end
