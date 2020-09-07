defmodule Tesla.Adapter.FinchTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Finch
  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody

  use Tesla.AdapterCase.SSL

  @pools %{
    @https => [
      conn_opts: [
        transport_opts: [
          cacertfile: "#{:code.priv_dir(:httparrot)}/ssl/server-ca.crt"
        ]
      ]
    ]
  }

  setup_all do
    start_supervised!({Finch, name: __MODULE__, pools: @pools})

    :ok
  end

  defp add_pool_opt(env) do
    case env.opts[:adapter] do
      nil ->
        Tesla.put_opt(env, :adapter, name: __MODULE__)

      kw ->
        Tesla.put_opt(env, :adapter, Keyword.put_new(kw, :name, __MODULE__))
    end
  end

  defp call(env, opts) do
    @adapter.call(add_pool_opt(env), opts)
  end
end
