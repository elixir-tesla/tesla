defmodule Tesla.AdapterCase do
  defmacro __using__(adapter: adapter) do
    quote do
      @adapter unquote(adapter)
      @http "http://localhost:#{Application.compile_env(:httparrot, :http_port)}"
      @https "https://localhost:#{Application.compile_env(:httparrot, :https_port)}"

      defp call(env, opts \\ []) do
        {mod, adapter_opts} =
          case @adapter do
            {mod, opts} -> {mod, opts}
            mod -> {mod, []}
          end

        mod.call(env, Keyword.merge(opts, adapter_opts))
      end
    end
  end
end
