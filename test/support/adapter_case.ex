defmodule Tesla.AdapterCase do
  defmacro __using__(adapter: adapter) do
    quote do
      @adapter unquote(adapter)
      @url "http://localhost:#{Application.get_env(:httparrot, :http_port)}"

      defp call(env, opts \\ []) do
        @adapter.call(env, opts)
      end
    end
  end
end
