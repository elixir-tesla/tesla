defmodule Tesla.Adapter.GunTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Gun
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.SSL

  test "fallback adapter timeout option" do
    request = %Env{
      method: :get,
      url: "#{@http}/delay/2"
    }

    assert {:error, :timeout} = call(request, timeout: 1_000)
  end

  test "max_body option" do
    request = %Env{
      method: :get,
      url: "#{@http}/get",
      query: [
        message: "Hello world!"
      ]
    }

    assert {:error, :body_too_large} = call(request, max_body: 5)
  end

  test "without slash" do
    request = %Env{
      method: :get,
      url: "#{@http}"
    }

    assert {:ok, %Env{} = response} = call(request)
    assert response.status == 400
  end

  test "response stream" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream/10"
    }

    assert {:ok, %Env{} = response} = call(request)
    assert response.status == 200
  end

  test "read response body in chunks" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream/10"
    }

    assert {:ok, %Env{} = response} = call(request, chunks_response: true)
    assert response.status == 200
    %{pid: pid, stream: stream, opts: opts} = response.body
    assert opts[:chunks_response]
    assert is_pid(pid)
    assert is_reference(stream)

    assert read_body(pid, stream) != []
  end

  test "read response body in stream" do
    request = %Env{
      method: :get,
      url: "#{@http}/stream/10"
    }

    assert {:ok, %Env{} = response} = call(request, stream_response: true)
    assert response.status == 200
    assert is_function(response.body)
    assert Enum.to_list(response.body) != []
  end

  defp read_body(pid, stream, acc \\ []) do
    case Tesla.Adapter.Gun.read_chunk(pid, stream, timeout: 1_000) do
      {:fin, body} ->
        :ok = :gun.close(pid)
        [body | acc]

      {:nofin, part} ->
        read_body(pid, stream, [part | acc])
    end
  end
end
