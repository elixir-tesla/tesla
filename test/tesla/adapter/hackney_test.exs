defmodule Tesla.Adapter.HackneyTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Hackney
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.SSL

  alias Tesla.Env

  test "get with `with_body: true` option" do
    request = %Env{
      method: :get,
      url: "#{@http}/ip"
    }

    assert %Env{} = response = call(request, with_body: true)
    assert response.status == 200
  end
end
