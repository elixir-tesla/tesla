defmodule Tesla.Adapter.HackneyTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Hackney
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody

  use Tesla.AdapterCase.SSL,
    ssl_options: [
      cacertfile: "#{:code.priv_dir(:httparrot)}/ssl/server-ca.crt"
    ]

  alias Tesla.Env

  test "get with `with_body: true` option" do
    request = %Env{
      method: :get,
      url: "#{@http}/ip"
    }

    assert {:ok, %Env{} = response} = call(request, with_body: true)
    assert response.status == 200
  end

  test "get with `with_body: true` option even when async" do
    request = %Env{
      method: :get,
      url: "#{@http}/ip"
    }

    assert {:ok, %Env{} = response} = call(request, with_body: true, async: true)
    assert response.status == 200
  end
end
