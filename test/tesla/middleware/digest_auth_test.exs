defmodule Tesla.Middleware.DigestAuthTest do
  use ExUnit.Case, async: false

  defmodule DigestClient do
    use Tesla

    adapter fn env ->
      {:ok,
       cond do
         env.url == "/no-digest-auth" ->
           env

         Tesla.get_header(env, "authorization") ->
           env

         true ->
           Tesla.put_headers(env, [
             {"www-authenticate",
              """
              Digest realm="testrealm@host.com",
              qop="auth,auth-int",
              nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093",
              opaque="5ccc069c403ebaf9f0171e9517f40e41"
              """}
           ])
       end}
    end

    def client(username, password, opts \\ %{}) do
      Tesla.client([
        {
          Tesla.Middleware.DigestAuth,
          Map.merge(
            %{
              username: username,
              password: password,
              cnonce_fn: fn -> "0a4f113b" end,
              nc: "00000001"
            },
            opts
          )
        }
      ])
    end
  end

  defmodule DigestClientWithDefaults do
    use Tesla

    def client do
      Tesla.client([
        {Tesla.Middleware.DigestAuth, nil}
      ])
    end
  end

  test "sends request with proper authorization header" do
    assert {:ok, request} =
             DigestClient.client("Mufasa", "Circle Of Life")
             |> DigestClient.get("/dir/index.html")

    auth_header = Tesla.get_header(request, "authorization")

    assert auth_header =~ ~r/^Digest /
    assert auth_header =~ "username=\"Mufasa\""
    assert auth_header =~ "realm=\"testrealm@host.com\""
    assert auth_header =~ "algorithm=MD5"
    assert auth_header =~ "qop=auth"
    assert auth_header =~ "uri=\"/dir/index.html\""
    assert auth_header =~ "nonce=\"dcd98b7102dd2f0e8b11d0f600bfb0c093\""
    assert auth_header =~ "nc=00000001"
    assert auth_header =~ "cnonce=\"0a4f113b\""
    assert auth_header =~ "response=\"6629fae49393a05397450978507c4ef1\""
  end

  test "has default values for username and cn" do
    assert {:ok, response} = DigestClientWithDefaults.client() |> DigestClient.get("/")
    auth_header = Tesla.get_header(response, "authorization")

    assert auth_header =~ "username=\"\""
    assert auth_header =~ "nc=00000000"
  end

  test "generates different cnonce with each request by default" do
    assert {:ok, env} = DigestClientWithDefaults.client() |> DigestClient.get("/")
    [_, cnonce_1 | _] = Regex.run(~r/cnonce="(.*?)"/, Tesla.get_header(env, "authorization"))

    assert {:ok, env} = DigestClientWithDefaults.client() |> DigestClient.get("/")
    [_, cnonce_2 | _] = Regex.run(~r/cnonce="(.*?)"/, Tesla.get_header(env, "authorization"))

    assert cnonce_1 != cnonce_2
  end

  test "works when passing custom opts" do
    assert {:ok, request} =
             DigestClientWithDefaults.client() |> DigestClient.get("/", opts: [hodor: "hodor"])

    assert request.opts == [hodor: "hodor"]
  end

  test "ignores digest auth when server doesn't respond with www-authenticate header" do
    assert {:ok, response} =
             DigestClientWithDefaults.client() |> DigestClient.get("/no-digest-auth")

    refute Tesla.get_header(response, "authorization")
  end
end
