defmodule Tesla.AdapterCase do
  defmacro __using__(adapter: adapter) do
    quote do
      @adapter unquote(adapter)
      # Needed for SSL test with certificate verification
      if @adapter == Tesla.Adapter.Ibrowse do
        @http "http://0.0.0.0:#{Application.get_env(:httparrot, :http_port)}"
        @https "https://0.0.0.0:#{Application.get_env(:httparrot, :https_port)}"
      else
        @http "http://localhost:#{Application.get_env(:httparrot, :http_port)}"
        @https "https://localhost:#{Application.get_env(:httparrot, :https_port)}"
      end

      defp call(env, opts \\ []) do
        @adapter.call(env, opts)
      end
    end
  end
end
