defmodule Tesla.AdapterCase do
  defmacro __using__(adapter: adapter) do
    quote do
      @adapter unquote(adapter)
      @http "http://localhost:#{Application.get_env(:httparrot, :http_port)}"
      @https "https://localhost:#{Application.get_env(:httparrot, :https_port)}"

      defp call(env, opts \\ []) do
        @adapter.call(env, opts)
      end

      defoverridable call: 2
    end
  end
end
