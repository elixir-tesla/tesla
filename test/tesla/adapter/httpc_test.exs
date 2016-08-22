defmodule HttpcTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla.Builder

    adapter :httpc
  end

  test "basic get request" do
    response = Client.get("http://httpbin.org/ip")
    assert response.status == 200
  end

  test "basic post request" do
    response = Client.post("http://httpbin.org/post", "some-post-data")
    assert response.status == 200
    assert Regex.match?(~r/some-post-data/, to_string(response.body))
  end
end
