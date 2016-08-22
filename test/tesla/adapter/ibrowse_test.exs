defmodule IbrowseTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla.Builder

    adapter :ibrowse
  end

  setup do
    Application.ensure_started(:ibrowse)
    :ok
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

  test "async requests" do
    {:ok, _id} = Client.get("http://httpbin.org/ip", respond_to: self)

    assert_receive {:tesla_response, _}, 2000
  end

  test "async requests parameters" do
    {:ok, _id} = Client.get("http://httpbin.org/ip", respond_to: self)

    receive do
      {:tesla_response, res} ->
        assert res.status == 200
    after
      2000 -> raise "Timeout"
    end
  end

end
