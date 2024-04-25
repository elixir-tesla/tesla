defmodule Tesla.Adapter.FinchTest do
  use ExUnit.Case

  @finch_name MyFinch

  use Tesla.AdapterCase, adapter: {Tesla.Adapter.Finch, [name: @finch_name]}
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.StreamResponseBody
  use Tesla.AdapterCase.SSL

  setup do
    opts = [
      name: @finch_name,
      pools: %{
        @https => [
          conn_opts: [
            transport_opts: [cacertfile: "#{:code.priv_dir(:httparrot)}/ssl/server-ca.crt"]
          ]
        ]
      }
    ]

    start_supervised!({Finch, opts})
    :ok
  end

  test "Delay request" do
    request = %Env{
      method: :head,
      url: "#{@http}/delay/1"
    }

    assert {:error, :timeout} = call(request, receive_timeout: 100)
  end

  test "Delay request with stream" do
    request = %Env{
      method: :head,
      url: "#{@http}/delay/1"
    }

    assert {:error, :timeout} = call(request, receive_timeout: 100, response: :stream)
  end
end
