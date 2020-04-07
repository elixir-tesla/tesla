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
    assert is_reference(response.body) == true
  end

  test "request timeout error" do
    request = %Env{
      method: :get,
      url: "#{@http}/delay/10",
      body: "test"
    }

    assert {:error, :timeout} = call(request, recv_timeout: 100)
  end

  test "stream request body: error" do
    body =
      Stream.unfold(5, fn
        0 -> nil
        3 -> {fn -> {:error, :fake_error} end, 2}
        n -> {to_string(n), n - 1}
      end)

    request = %Env{
      method: :post,
      url: "#{@http}/post",
      body: body
    }

    assert {:error, :fake_error} = call(request)
  end
end
