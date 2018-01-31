defmodule Tesla.Migration do
  @issue_159 "https://github.com/teamon/tesla/wiki/0.x-to-1.0-Migration-Guide#dropped-aliases-support-159"

  def breaking_alias!(_kind, _name, nil), do: nil
  def breaking_alias!(kind, name, caller) do
    arity = local_function_arity(kind)
    unless Module.defines?(caller.module, {name, arity}) do
      raise CompileError, file: caller.file, line: caller.line, description:
        """

            #{kind |> to_string |> String.capitalize} aliases has been removed.
            Use full #{kind} name or define a local function #{name}/#{arity}

              #{snippet(caller)}

            See #{@issue_159}
        """
    end
  end

  defp local_function_arity(:adapter), do: 1
  defp local_function_arity(:middleware), do: 2

  defp snippet(caller) do
    caller.file
    |> File.read!()
    |> String.split("\n")
    |> Enum.at(caller.line - 1)
  rescue
    _ in File.Error -> ""
  end

  def breaking_alias_in_config!(module) do
    check_config(Application.get_env(:tesla, module, [])[:adapter], "config :tesla, #{inspect module}, adapter: ")
    check_config(Application.get_env(:tesla, :adapter), "config :tesla, adapter: ")
  end

  defp check_config(nil, _label), do: nil
  defp check_config({module, _opts}, label) do
    check_config(module, label)
  end
  defp check_config(module, label) do
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
