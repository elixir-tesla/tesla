defmodule Tesla.Middleware.TelemetryTest do
  use ExUnit.Case, async: true

  @moduletag capture_log: true

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

  setup do
    Application.ensure_all_started(:telemetry)

    on_exit(fn ->
      :telemetry.list_handlers([])
      |> Enum.each(&:telemetry.detach(&1.id))
    end)

    :ok
  end

  describe "Telemetry" do
    test "events are all emitted properly" do
      Enum.each(["/telemetry", "/telemetry_error"], fn path ->
        :telemetry.attach("start event", [:tesla, :request, :start], &echo_event/4, %{
          caller: self()
        })

        :telemetry.attach("stop event", [:tesla, :request, :stop], &echo_event/4, %{
          caller: self()
        })

        :telemetry.attach("legacy event", [:tesla, :request], &echo_event/4, %{caller: self()})

        Client.get(path)

        assert_receive {:event, [:tesla, :request, :start], %{system_time: time},
                        %{env: %Tesla.Env{url: path, method: :get}}}

        assert_receive {:event, [:tesla, :request, :stop], %{duration: time},
                        %{env: %Tesla.Env{url: path, method: :get}}}

        assert_receive {:event, [:tesla, :request], %{request_time: time}, %{result: result}}
      end)
    end

    test "with an exception raised" do
      :telemetry.attach("with_exception", [:tesla, :request, :exception], &echo_event/4, %{
        caller: self()
      })

      assert_raise RuntimeError, fn ->
        Client.get("/telemetry_exception")
      end

      assert_receive {:event, [:tesla, :request, :exception], %{duration: time},
                      %{kind: kind, reason: reason, stacktrace: stacktrace}}
    end
  end

  describe "with :telemetry_prefix config" do
    setup do
      Application.put_env(:tesla, Tesla.Middleware.Telemetry, telemetry_prefix: [:custom, :prefix])

      on_exit(fn ->
        Application.delete_env(:tesla, Tesla.Middleware.Telemetry)
      end)

      :ok
    end

    test "events are all emitted properly" do
      Enum.each(["/telemetry", "/telemetry_error"], fn path ->
        :telemetry.attach("start event", [:custom, :prefix, :request, :start], &echo_event/4, %{
          caller: self()
        })

        :telemetry.attach("stop event", [:custom, :prefix, :request, :stop], &echo_event/4, %{
          caller: self()
        })

        :telemetry.attach("legacy event", [:custom, :prefix, :request], &echo_event/4, %{
          caller: self()
        })

        Client.get(path)

        assert_receive {:event, [:custom, :prefix, :request, :start], %{system_time: time},
                        %{env: %Tesla.Env{url: path, method: :get}}}

        assert_receive {:event, [:custom, :prefix, :request, :stop], %{duration: time},
                        %{env: %Tesla.Env{url: path, method: :get}}}

        assert_receive {:event, [:custom, :prefix, :request], %{request_time: time},
                        %{result: result}}
      end)
    end

    test "with an exception raised" do
      :telemetry.attach(
        "with_exception",
        [:custom, :prefix, :request, :exception],
        &echo_event/4,
        %{caller: self()}
      )

      assert_raise RuntimeError, fn ->
        Client.get("/telemetry_exception")
      end

      assert_receive {:event, [:custom, :prefix, :request, :exception], %{duration: time},
                      %{kind: kind, reason: reason, stacktrace: stacktrace}}
    end
  end

  describe "with :telemetry_prefix option" do
    defmodule ClientWithTelemetryPrefix do
      use Tesla

      plug Tesla.Middleware.Telemetry, telemetry_prefix: [:custom, :prefix]

      adapter fn env ->
        case env.url do
          "/telemetry" -> {:ok, env}
          "/telemetry_error" -> {:error, :econnrefused}
          "/telemetry_exception" -> raise "some exception"
        end
      end
    end

    test "events are all emitted properly" do
      Enum.each(["/telemetry", "/telemetry_error"], fn path ->
        :telemetry.attach("start event", [:custom, :prefix, :request, :start], &echo_event/4, %{
          caller: self()
        })

        :telemetry.attach("stop event", [:custom, :prefix, :request, :stop], &echo_event/4, %{
          caller: self()
        })

        :telemetry.attach("legacy event", [:custom, :prefix, :request], &echo_event/4, %{
          caller: self()
        })

        ClientWithTelemetryPrefix.get(path)

        assert_receive {:event, [:custom, :prefix, :request, :start], %{system_time: time},
                        %{env: %Tesla.Env{url: path, method: :get}}}

        assert_receive {:event, [:custom, :prefix, :request, :stop], %{duration: time},
                        %{env: %Tesla.Env{url: path, method: :get}}}

        assert_receive {:event, [:custom, :prefix, :request], %{request_time: time},
                        %{result: result}}
      end)
    end

    test "with an exception raised" do
      :telemetry.attach(
        "with_exception",
        [:custom, :prefix, :request, :exception],
        &echo_event/4,
        %{caller: self()}
      )

      assert_raise RuntimeError, fn ->
        ClientWithTelemetryPrefix.get("/telemetry_exception")
      end

      assert_receive {:event, [:custom, :prefix, :request, :exception], %{duration: time},
                      %{kind: kind, reason: reason, stacktrace: stacktrace}}
    end
  end

  describe "with :telemetry_prefix config and option override" do
    setup do
      Application.put_env(:tesla, Tesla.Middleware.Telemetry,
        telemetry_prefix: [:different, :prefix]
      )

      on_exit(fn ->
        Application.delete_env(:tesla, Tesla.Middleware.Telemetry)
      end)

      :ok
    end

    defmodule ClientConfigWithTelemetryPrefix do
      use Tesla

      plug Tesla.Middleware.Telemetry, telemetry_prefix: [:custom, :prefix]

      adapter fn env ->
        case env.url do
          "/telemetry" -> {:ok, env}
          "/telemetry_error" -> {:error, :econnrefused}
          "/telemetry_exception" -> raise "some exception"
        end
      end
    end

    test "events are all emitted properly" do
      Enum.each(["/telemetry", "/telemetry_error"], fn path ->
        :telemetry.attach("start event", [:custom, :prefix, :request, :start], &echo_event/4, %{
          caller: self()
        })

        :telemetry.attach("stop event", [:custom, :prefix, :request, :stop], &echo_event/4, %{
          caller: self()
        })

        :telemetry.attach("legacy event", [:custom, :prefix, :request], &echo_event/4, %{
          caller: self()
        })

        ClientConfigWithTelemetryPrefix.get(path)

        assert_receive {:event, [:custom, :prefix, :request, :start], %{system_time: time},
                        %{env: %Tesla.Env{url: path, method: :get}}}

        assert_receive {:event, [:custom, :prefix, :request, :stop], %{duration: time},
                        %{env: %Tesla.Env{url: path, method: :get}}}

        assert_receive {:event, [:custom, :prefix, :request], %{request_time: time},
                        %{result: result}}
      end)
    end

    test "with an exception raised" do
      :telemetry.attach(
        "with_exception",
        [:custom, :prefix, :request, :exception],
        &echo_event/4,
        %{caller: self()}
      )

      assert_raise RuntimeError, fn ->
        ClientConfigWithTelemetryPrefix.get("/telemetry_exception")
      end

      assert_receive {:event, [:custom, :prefix, :request, :exception], %{duration: time},
                      %{kind: kind, reason: reason, stacktrace: stacktrace}}
    end
  end

  def echo_event(event, measurements, metadata, config) do
    send(config.caller, {:event, event, measurements, metadata})
  end
end
