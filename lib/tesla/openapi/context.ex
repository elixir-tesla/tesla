defmodule Tesla.OpenApi.Context do
  def get_spec(), do: get(:__tesla__spec)
  def put_spec(spec), do: put(:__tesla__spec, spec)

  def get_caller(), do: get(:__tesla__caller)
  def put_caller(caller), do: put(:__tesla__caller, caller)

  def get_config(), do: get(:__tesla__config)
  def put_config(config), do: put(:__tesla__config, config)

  defp get(key) do
    case :erlang.get(key) do
      :undefined -> raise "#{key} not set"
      val -> val
    end
  end

  defp put(key, val), do: :erlang.put(key, val)
end
