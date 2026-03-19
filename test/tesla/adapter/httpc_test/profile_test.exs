defmodule Tesla.Adapter.HttpcTest.Profile do
  @profile :test_profile

  use ExUnit.Case
  use Tesla.AdapterCase, adapter: {Tesla.Adapter.Httpc, profile: @profile}

  alias Tesla.Env

  setup do
    {:ok, _pid} = :inets.start(:httpc, profile: @profile)

    on_exit(fn -> :inets.stop(:httpc, @profile) end)
  end

  test "a non-default profile is used" do
    request = %Env{
      method: :get,
      url: "#{@http}/ip"
    }

    assert {:ok, %Env{} = response} = call(request)
    assert response.status == 200
  end
end
