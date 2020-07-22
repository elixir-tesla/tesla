defmodule Tesla.AdapterCase do
  defmacro __using__(adapter: adapter) do
    quote do
      @adapter unquote(adapter)
      @http "http://localhost:#{Application.get_env(:httparrot, :http_port)}"
      @https "https://localhost:#{Application.get_env(:httparrot, :https_port)}"

      defp call(env, opts \\ []) do
        case @adapter do
          {adapter, adapter_opts} -> adapter.call(env, Keyword.merge(opts, adapter_opts))
          adapter -> adapter.call(env, opts)
        end
      end
    end
  end
end
