defmodule Tesla.Migration do
  @moduledoc false
  ## ALIASES

  @breaking_alias "https://github.com/teamon/tesla/wiki/0.x-to-1.0-Migration-Guide#dropped-aliases-support-159"
  @breaking_headers_map "https://github.com/teamon/tesla/wiki/0.x-to-1.0-Migration-Guide#headers-are-now-a-list-160"
  @breaking_client_fun "https://github.com/teamon/tesla/wiki/0.x-to-1.0-Migration-Guide#dropped-client-as-function-176"

  def breaking_alias!(_kind, _name, nil), do: nil

  def breaking_alias!(kind, name, caller) do
    raise CompileError,
      file: caller.file,
      line: caller.line,
      description: """

          #{kind |> to_string |> String.capitalize()} aliases and local functions has been removed.
          Use full #{kind} name or define a middleware module #{
        name |> to_string() |> String.capitalize()
      }

            #{snippet(caller)}

          See #{@breaking_alias}
      """
  end

  def breaking_alias_in_config!(module) do
    check_config(
      Application.get_env(:tesla, module, [])[:adapter],
      "config :tesla, #{inspect(module)}, adapter: "
    )

    check_config(Application.get_env(:tesla, :adapter), "config :tesla, adapter: ")
  end

  defp check_config(nil, _label), do: nil

  defp check_config({module, _opts}, label) do
    check_config(module, label)
  end

  defp check_config(module, label) do
    unless elixir_module?(module) do
      raise CompileError,
        description: """

          Calling

              #{label}#{inspect(module)}

          with atom as argument has been deprecated

          Use

              #{label}Tesla.Adapter.Name

          instead

          See #{@breaking_alias}
        """
    end
  end

  ## HEADERS AS LIST

  def breaking_headers_map!(
        {:__aliases__, _, [:Tesla, :Middleware, :Headers]},
        {:%{}, _, _},
        caller
      ) do
    raise CompileError,
      file: caller.file,
      line: caller.line,
      description: """

          Headers are now a list instead of a map.

            #{snippet(caller)}

          See #{@breaking_headers_map}
      """
  end

  def breaking_headers_map!(_middleware, _opts, _caller), do: nil

  ## CLIENT FUNCTION

  def client_function! do
    raise RuntimeError,
      message: """

        Using anonymous function as client has been removed.
        Use `Tesla.client/2` instead

        See #{@breaking_client_fun}
      """
  end

  ## UTILS

  defp elixir_module?(atom) do
    atom |> Atom.to_string() |> String.starts_with?("Elixir.")
  end

  defp snippet(caller) do
    caller.file
    |> File.read!()
    |> String.split("\n")
    |> Enum.at(caller.line - 1)
  rescue
    _ in File.Error -> ""
  end
end
