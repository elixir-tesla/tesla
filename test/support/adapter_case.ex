defmodule Tesla.AdapterCase do
  defmacro __using__(opts) do
    quote do
      @adapter unquote(Keyword.fetch!(opts, :adapter))
      @adapter_opts unquote(opts[:adapter_opts] || [])
      @http "http://localhost:#{Application.get_env(:httparrot, :http_port)}"
      @https "https://localhost:#{Application.get_env(:httparrot, :https_port)}"

      defp call(env, opts \\ []) do
        @adapter.call(env, Keyword.merge(opts, @adapter_opts))
      end
    end
  end
end
