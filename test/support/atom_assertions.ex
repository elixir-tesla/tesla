defmodule Tesla.TestSupport.AtomAssertions do
  @moduledoc """
  Assertions about the VM atom table.

  Prefer these over comparing `:erlang.system_info(:atom_count)`, which counts
  atoms created by every other test running at the same time.
  """

  @doc """
  Asserts that no atom named `name` exists in the VM.

  Build `name` at runtime with a unique suffix so that nothing but the code
  under test can create the atom.
  """
  defmacro refute_atom_exists(name) do
    quote do
      name = unquote(name)

      try do
        String.to_existing_atom(name)
      rescue
        ArgumentError -> :ok
      else
        atom ->
          ExUnit.Assertions.flunk("expected no atom named #{inspect(name)}, got #{inspect(atom)}")
      end
    end
  end
end
