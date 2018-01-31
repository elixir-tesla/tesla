defmodule Tesla.Migration do
  @issue_159 "https://github.com/teamon/tesla/wiki/0.x-to-1.0-Migration-Guide#dropped-aliases-support-159"

  def raise_if_atom!(fun, scope, arg) when is_atom(arg) do
    raise CompileError, description:
    """
      Calling `#{fun}` with atom as argument has been deprecated

      Use `#{fun} #{inspect scope}.Name` instead

      See #{@issue_159}
    """
  end
  def raise_if_atom!(_fun, _scope, _arg), do: nil


  def raise_if_atom_in_config!(module) do
    check_config_atom(Application.get_env(:tesla, module, [])[:adapter], "config :tesla, #{inspect module}, adapter: ")
    check_config_atom(Application.get_env(:tesla, :adapter), "config :tesla, adapter: ")
  end

  defp check_config_atom(nil, _label), do: nil
  defp check_config_atom({module, _opts}, label) do
    check_config_atom(module, label)
  end
  defp check_config_atom(module, label) do
    Code.ensure_loaded(module)
    unless function_exported?(module, :call, 2) do
      raise CompileError, description:
      """

        Calling

            #{label}#{inspect module}

        with atom as argument has been deprecated

        Use

            #{label}Tesla.Adapter.Name

        instead

        See #{@issue_159}
      """
    end
  end
end
