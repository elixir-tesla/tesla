defmodule Tesla.Adapter.HackneyTest do
  use ExUnit.Case
  use Tesla.AdapterCase.Basic, adapter: :hackney
  use Tesla.AdapterCase.StreamRequestBody, adapter: :hackney
  use Tesla.AdapterCase.SSL, adapter: :hackney

  test "get with `with_body: true` option" do
    defmodule Client do
      use Tesla

      adapter :hackney, with_body: true
    end

    response = Client.get("#{Tesla.AdapterCase.http_url()}/ip")
    assert response.status == 200
  end
end
