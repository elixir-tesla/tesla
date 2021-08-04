defmodule Tesla.Adapter.HttpcTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Httpc
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody

  use Tesla.AdapterCase.SSL,
    ssl: [
      verify: :verify_peer,
      cacertfile: "#{:code.priv_dir(:httparrot)}/ssl/server-ca.crt"
    ]

  # see https://github.com/teamon/tesla/issues/147
  test "Set content-type for DELETE requests" do
    env = %Env{
      method: :delete,
      url: "#{@http}/delete"
    }

    env = Tesla.put_header(env, "content-type", "text/plain")

    assert {:ok, %Env{} = response} = call(env)
    assert response.status == 200

    {:ok, data} = Jason.decode(response.body)

    assert data["headers"]["content-type"] == "text/plain"
  end
end
