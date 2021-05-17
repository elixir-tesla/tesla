defmodule Tesla.Middleware.Config do
  @moduledoc false

  def build!(middleware, schema, opts) do
    global_keys =
      schema
      |> Enum.filter(fn {_k, v} -> v[:global] == true end)
      |> Enum.map(fn {k, _v} -> k end)

    :tesla
    |> Application.get_env(middleware, [])
    |> Keyword.take(global_keys)
    |> Keyword.merge(opts)
    |> NimbleOptions.validate(to_nimble(schema))
    |> handle_validate(middleware)
  end

  def docs(schema) do
    schema
    |> to_nimble()
    |> NimbleOptions.docs()
  end

  defp to_nimble(schema) do
    Enum.map(schema, fn {k, v} ->
      {global, value} = Keyword.pop(v, :global, false)

      if global == true do
        {k,
         Keyword.update(value, :doc, "", fn doc ->
           doc <> " Configurable via application configuration."
         end)}
      else
        {k, value}
      end
    end)
  end

  defp handle_validate({:ok, opts}, _middleware), do: opts

  defp handle_validate({:error, error}, middleware) do
    raise ArgumentError, format_error(error, middleware)
  end

  defp format_error(%NimbleOptions.ValidationError{keys_path: [], message: message}, middleware) do
    "invalid configuration given to middleware #{inspect(middleware)}, " <> message
  end

  defp format_error(
         %NimbleOptions.ValidationError{keys_path: keys_path, message: message},
         middleware
       ) do
    "invalid configuration given to to middleware #{inspect(middleware)} for key #{
      inspect(keys_path)
    }, " <>
      message
  end
end
