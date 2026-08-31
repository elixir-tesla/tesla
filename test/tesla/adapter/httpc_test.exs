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

  # :httpc accepts only a fixed set of method atoms, which as of OTP 29 does
  # not include QUERY (RFC 10008). The error is passed through from :httpc,
  # so QUERY starts working automatically once OTP adds support for it -
  # accept both outcomes to stay green across OTP versions.
  test "QUERY request" do
    env = %Env{
      method: :query,
      url: "#{@http}/post",
      body: "select=surname,givenname&limit=10",
      headers: [{"content-type", "application/x-www-form-urlencoded"}]
    }

    case call(env) do
      {:error, reason} -> assert reason == :invalid_method
      {:ok, %Env{} = response} -> assert response.status in 100..599
    end
  end

  test "Multipart content-type wins over a request supplied content-type" do
    mp = Multipart.new() |> Multipart.add_field("field1", "foo")

    env = %Env{
      method: :post,
      url: "#{@http}/post",
      headers: [{"content-type", "application/json"}],
      body: mp
    }

    assert {:ok, %Env{} = response} = call(env)
    assert response.status == 200

    {:ok, data} = Jason.decode(response.body)

    assert data["headers"]["content-type"] == "multipart/form-data; boundary=#{mp.boundary}"
    assert data["form"] == %{"field1" => "foo"}
  end

  test "Multipart content-type wins regardless of the request header casing" do
    mp = Multipart.new() |> Multipart.add_field("field1", "foo")

    env = %Env{
      method: :post,
      url: "#{@http}/post",
      headers: [{"Content-Type", "application/json"}, {"x-keep", "yes"}],
      body: mp
    }

    assert {:ok, %Env{} = response} = call(env)
    assert response.status == 200

    {:ok, data} = Jason.decode(response.body)

    assert data["headers"]["content-type"] == "multipart/form-data; boundary=#{mp.boundary}"
    assert data["headers"]["x-keep"] == "yes"
    assert data["form"] == %{"field1" => "foo"}
  end

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

  test "binary body format is passed through untouched" do
    env = %Env{method: :get, url: "#{@http}/base64/dGVzbGE"}

    assert {:ok, %Env{} = response} = call(env, body_format: :binary)
    assert response.status == 200
    assert response.body == "tesla"
  end
end
