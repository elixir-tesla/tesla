defmodule Tesla.Middleware.TestCase do
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
      test "return Tesla.Env and execute rest of the stack" do
        require Tesla


        client = Tesla.build_client([
          {unquote(middleware), nil},
          {Exec, self}
        ])

        response = Client.get(client, "/")

        assert %Tesla.Env{} = response
        assert_receive :before
        assert_receive :after
      end
    end
  end
end
