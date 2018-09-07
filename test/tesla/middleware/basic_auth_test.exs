defmodule Tesla.Middleware.BasicAuthTest do
  use ExUnit.Case

  defmodule BasicClient do
    use Tesla

    adapter fn env ->
      case env.url do
        "/basic-auth" -> {:ok, env}
      end
    end

    def client(username, password, opts \\ %{}) do
      Tesla.client([
        {
          Tesla.Middleware.BasicAuth,
          Map.merge(
            %{
              username: username,
              password: password
            },
            opts
          )
        }
      ])
    end

    def client() do
      Tesla.client([Tesla.Middleware.BasicAuth])
    end
  end

  defmodule BasicClientPlugOptions do
    use Tesla
    plug Tesla.Middleware.BasicAuth, username: "Auth", password: "Test"

    adapter fn env ->
      case env.url do
        "/basic-auth" -> {:ok, env}
      end
    end
  end

  test "sends request with proper authorization header" do
    username = "Aladdin"
    password = "OpenSesame"

    base_64_encoded = Base.encode64("#{username}:#{password}")
    assert base_64_encoded == "QWxhZGRpbjpPcGVuU2VzYW1l"

    {:ok, request} = BasicClient.client(username, password) |> BasicClient.get("/basic-auth")
    auth_header = Tesla.get_header(request, "authorization")

    assert auth_header == "Basic #{base_64_encoded}"
  end

  test "it correctly encodes a blank username and password" do
    base_64_encoded = Base.encode64(":")
    assert base_64_encoded == "Og=="

    {:ok, request} = BasicClient.client() |> BasicClient.get("/basic-auth")
    auth_header = Tesla.get_header(request, "authorization")

    assert auth_header == "Basic #{base_64_encoded}"
  end

  test "username and password can be passed to plug directly" do
    username = "Auth"
    password = "Test"

    base_64_encoded = Base.encode64("#{username}:#{password}")
    assert base_64_encoded == "QXV0aDpUZXN0"

    {:ok, request} = BasicClientPlugOptions.get("/basic-auth")
    auth_header = Tesla.get_header(request, "authorization")

    assert auth_header == "Basic #{base_64_encoded}"
  end
end
