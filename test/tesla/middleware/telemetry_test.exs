defmodule Tesla.Middleware.TelemetryTest do
  use ExUnit.Case, async: true

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Telemetry

    adapter fn env ->
      case env.url do
        "/telemetry" -> {:ok, env}
        "/telemetry_error" -> {:error, :econnrefused}
        "/telemetry_exception" -> raise "some exception"
      end
    end
  end

  defmodule ClientWithOptions do
    use Tesla

    plug Tesla.Middleware.Telemetry, event_prefix: [:my_client]

    adapter fn env ->
      case env.url do
        "/telemetry" -> {:ok, env}
      end
    end
  end

  setup do
    Application.ensure_all_started(:telemetry)

    on_exit(fn ->
      :telemetry.list_handlers([])
      |> Enum.each(&:telemetry.detach(&1.id))
    end)

    :ok
  end

  test "accepts options" do
    :telemetry.attach("with_opts", [:my_client, :tesla, :request, :stop], &echo_event/4, %{
      caller: self()
    })

    ClientWithOptions.get("/telemetry")

    assert_receive {:event, [:my_client, :tesla, :request, :stop], %{duration: time},
                    %{env: %Tesla.Env{url: "/telemetry", method: :get}}}
  end

  test "with default options" do
    :telemetry.attach("with_default_opts_start", [:tesla, :request, :start], &echo_event/4, %{
      caller: self()
    })

    :telemetry.attach("with_default_opts_stop", [:tesla, :request, :stop], &echo_event/4, %{
      caller: self()
    })

    :telemetry.attach("with_default_opts_legacy", [:tesla, :request, :stop], &echo_event/4, %{
      caller: self()
    })

    Client.get("/telemetry")

    assert_receive {:event, [:tesla, :request, :start], %{time: time},
                    %{env: %Tesla.Env{url: "/telemetry", method: :get}}}

    assert_receive {:event, [:tesla, :request, :stop], %{duration: time},
                    %{env: %Tesla.Env{url: "/telemetry", method: :get}}}
  end

  test "legacy_event_emitted_by_default" do
    :telemetry.attach("with_default_opts_legacy", [:tesla, :request], &echo_event/4, %{
      caller: self()
    })

    Client.get("/telemetry")

    assert_receive {:event, [:tesla, :request], %{request_time: time}, %{result: result}}
  end

  test "with an error returned" do
    :telemetry.attach("with_error", [:tesla, :request, :error], &echo_event/4, %{caller: self()})

    :telemetry.attach("with_error_gets_stop", [:tesla, :request, :stop], &echo_event/4, %{
      caller: self()
    })

    Client.get("/telemetry_error")

    assert_receive {:event, [:tesla, :request, :error], %{value: 1},
                    %{
                      env: %Tesla.Env{url: "/telemetry_error", method: :get},
                      kind: kind,
                      reason: :econnrefused,
                      stacktrace: []
                    }}

    assert_receive {:event, [:tesla, :request, :stop], %{duration: time},
                    %{
                      env: %Tesla.Env{url: "/telemetry_error", method: :get}
                    }}
  end

  test "with an exception raised" do
    :telemetry.attach("with_exception", [:tesla, :request, :error], &echo_event/4, %{
      caller: self()
    })

    :telemetry.attach("with_exception_gets_stop", [:tesla, :request, :stop], &echo_event/4, %{
      caller: self()
    })

    assert_raise RuntimeError, fn ->
      Client.get("/telemetry_exception")
    end

    assert_receive {:event, [:tesla, :request, :error], %{value: 1},
                    %{
                      env: %Tesla.Env{url: "/telemetry_exception", method: :get},
                      kind: kind,
                      reason: reason,
                      stacktrace: stacktrace
                    }}

    assert_receive {:event, [:tesla, :request, :stop], %{duration: time},
                    %{
                      env: %Tesla.Env{url: "/telemetry_exception", method: :get}
                    }}
  end

  def echo_event(event, measurements, metadata, config) do
    send(config.caller, {:event, event, measurements, metadata})
  end
end
