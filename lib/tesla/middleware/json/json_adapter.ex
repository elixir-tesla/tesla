if Code.ensure_loaded?(JSON) do
  defmodule Tesla.Middleware.JSON.JSONAdapter do
    @moduledoc false
    # An adapter for Elixir's built-in JSON module introduced in Elixir 1.18
    # that adjusts for Tesla's assumptions about a JSON engine, which are not satisfied by
    # Elixir's JSON module. The assumptions are:
    # - the module provides encode/2 and decode/2 functions
    # - the 2nd argument to the functions is opts
    # - the functions return {:ok, json} or {:error, reason} - not the case for JSON.encode!/2
    #
    # We do not support custom encoders and decoders.
    # The purpose of this adapter is to allow `engine: JSON` to be set easily. If more advanced
    # customization is required, the `:encode` and `:decode` functions can be supplied to the
    # middleware instead of the `:engine` option.
    def encode(data, _opts), do: {:ok, JSON.encode!(data)}
    def decode(binary, _opts), do: JSON.decode(binary)
  end
end
