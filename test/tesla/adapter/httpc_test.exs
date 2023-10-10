defmodule Tesla.Adapter.HttpcTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Httpc
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody

  use Tesla.AdapterCase.SSL,
    ssl: [
      verify: :verify_peer,
      cacertfile: Path.join([to_string(:code.priv_dir(:httparrot)), "/ssl/server-ca.crt"])
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

  test "that get uses the correct request" do
    env = %Env{
      method: :get,
      body: "",
      url: "#{@http}/get"
    }

    env = Tesla.put_header(env, "content-type", "text/plain")

    assert {:ok, %Env{} = response} = call(env)
    assert response.status == 200

    {:ok, data} = Jason.decode(response.body)

    assert data["headers"]["content-type"] == "text/plain"
  end

  describe "badssl" do
    @describetag :integration

    test "expired.badssl.com" do
      assert {:error, :econnrefused} = Tesla.get(Tesla.client([], Tesla.Adapter.Httpc), "https://expired.badssl.com")
    end

    test "wrong.host.badssl.com" do
      assert {:error, :econnrefused} = Tesla.get(Tesla.client([], Tesla.Adapter.Httpc), "https://wrong.host.badssl.com")
    end

    test "self-signed.badssl.com" do
      assert {:error, :econnrefused} = Tesla.get(Tesla.client([], Tesla.Adapter.Httpc), "https://self-signed.badssl.com")
    end

    test "untrusted-root.badssl.com" do
      assert {:error, :econnrefused} = Tesla.get(Tesla.client([], Tesla.Adapter.Httpc), "https://untrusted-root.badssl.com")
    end

    test "revoked.badssl.com" do
      assert {:error, :econnrefused} = Tesla.get(Tesla.client([], Tesla.Adapter.Httpc), "https://revoked.badssl.com")
    end
#    TODO: figure out how to test this
#    test "pinning-test.badssl.com" do
#      assert {:error, :econnrefused} = Tesla.get(Tesla.client([], Tesla.Adapter.Httpc), "https://pinning-test.badssl.com")
#    end
  end
end
