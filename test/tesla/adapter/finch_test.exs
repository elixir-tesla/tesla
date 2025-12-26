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

  test "Stream request handles errors without raising CaseClauseError" do
    # This test verifies that streaming errors (like proxy 403) are properly
    # handled in the callback and receive blocks instead of raising CaseClauseError.
    # Before the fix, an error during streaming would cause:
    #   (CaseClauseError) no case clause matching: {:error, error, nil}

    assert {:error, _} =
             Tesla.Adapter.Finch.call(
               %Tesla.Env{
                 method: :get,
                 url: "http://nonexistent.invalid",
                 body: nil,
                 headers: []
               },
               name: @finch_name,
               response: :stream,
               receive_timeout: 1000
             )
  end
end
