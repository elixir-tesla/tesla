defmodule Tesla.Middleware.TelemetryTest do
  use ExUnit.Case, async: true

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Telemetry

    adapter fn env ->
      case env.url do
        "/telemetry" -> {:ok, env}
        "/telemetry_error" -> {:error, :econnrefused}
      end
    end
  end

  setup do
    Application.ensure_all_started(:telemetry)
    :ok
  end

  test "Get the info from telemetry" do
    :telemetry.attach(
      "telemetry_test",
      [:tesla, :request],
      fn [:tesla, :request], %{request_time: time}, meta, _config ->
        send(self(), {:ok_called, is_integer(time), meta})
      end,
      nil
    )

    Client.get("/telemetry")

    assert_receive {:ok_called, true,
                    %{result: {:ok, %Tesla.Env{url: "/telemetry", method: :get}}}},
                   1000
  end

  test "Get the error from telemetry" do
    :telemetry.attach(
      "telemetry_test_error",
      [:tesla, :request],
      fn [:tesla, :request], %{request_time: time}, meta, _config ->
        send(self(), {:error_called, is_integer(time), meta})
      end,
      nil
    )

    Client.get("/telemetry_error")
    assert_receive {:error_called, true, %{result: {:error, :econnrefused}}}, 1000
  end
end
