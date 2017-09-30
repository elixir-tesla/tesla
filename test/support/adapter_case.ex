defmodule Tesla.AdapterCase do
  defmacro __using__([adapter: adapter]) do
    quote do
      @adapter  unquote(adapter)
      @url       "http://localhost:#{Application.get_env(:httparrot, :http_port)}"

      defp call(env, opts \\ []) do
        Tesla.Middleware.Normalize.call(env, [{@adapter, :call, [opts]}], [])
      end
    end
  end
end
