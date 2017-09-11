defmodule Tesla.Adapter.HackneyTest do
  use ExUnit.Case
  use Tesla.Adapter.TestCase.Basic, adapter: :hackney
  use Tesla.Adapter.TestCase.StreamRequestBody, adapter: :hackney
  use Tesla.Adapter.TestCase.SSL, adapter: :hackney

  test "get with `with_body: true` option" do
    defmodule Client do
      use Tesla

      adapter :hackney, with_body: true
    end

    response = Client.get("#{Tesla.Adapter.TestCase.http_url()}/ip")
    assert response.status == 200
  end
end
