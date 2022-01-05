defmodule Tesla.Error do
  defexception env: nil, stack: [], reason: nil

  def message(%Tesla.Error{env: %{url: url, method: method}, reason: reason}) do
    "#{inspect(reason)} (#{method |> to_string |> String.upcase()} #{url})"
  end
end
