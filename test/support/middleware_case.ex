defmodule Tesla.MiddlewareCase do
  defmodule Exec do
    def call(env, next, pid) do
      send pid, :before
      env = Tesla.run(env, next)
      send pid, :after
      env
    end
  end

  defmodule Client do
    use Tesla
    adapter fn env -> env end
  end

  defmacro __using__([middleware: middleware]) do
    quote do
      test "#{inspect unquote(middleware)}: return Tesla.Env and execute rest of the stack" do
        require Tesla


        client = Tesla.build_client([
          {unquote(middleware), nil},
          {Exec, self()}
        ])

        ExUnit.CaptureLog.capture_log(fn ->
          send self(), {:response, Client.get(client, "/")}
        end)

        response = receive do
          {:response, res} -> res
        end

        assert %Tesla.Env{} = response
        assert_receive :before
        assert_receive :after
      end
    end
  end
end
