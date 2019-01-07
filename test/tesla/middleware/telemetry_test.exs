defmodule Tesla.Middleware.TelemetryTest do
  use ExUnit.Case, async: false
  import Mock

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Telemetry

    adapter fn env ->
      case env.url do
        "/telemetry" -> {:ok, env}
      end
    end
  end

  defmodule Telemetry do
    def telemetry_handler(_, _, _, _) do end
  end
 
  setup do
    :telemetry_app.start(nil, nil)
    :ok
  end

  test "Get the info from telemetry" do
    tag = [:tesla, :telemetry, :traffic]
    with_mock Telemetry, [telemetry_handler: fn(tag, response, meta, _config) ->
                        IO.inspect "Do Body Checkibg"
                      end] do
      :telemetry.attach("telemetry_test", tag, &Telemetry.telemetry_handler/4, nil)
      Client.get("/telemetry")
      assert_called Telemetry.telemetry_handler(:_, :_, :_, :_)
    end
  end
end
