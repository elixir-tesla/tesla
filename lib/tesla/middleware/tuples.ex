defmodule Tesla.Middleware.Tuples do
  @behaviour Tesla.Middleware

  @moduledoc """
  Return `:ok` / `:error` tuples for successful HTTP transactions, i.e. when the
  request is completed (no network errors etc) - but it can still be an
  application-level error (i.e. 404 or 500).

  **NOTE**: This middleware must be included as the first in the stack (before
  other middleware)

  ### Example usage

  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.Tuples
    plug Tesla.Middleware.JSON
  end
  ```

  ### Options
  - `:rescue_errors` - list exceptions to be rescued, defaults to `:all` (See below)

  The default behaviour is to rescue Tesla.Error exceptions but let other pass
  through. It can be customized by passing a `rescue_error:` option:

  ### Rescue other exceptions

  ```
  plug Tesla.Middleware.Tuples, rescue_errors: [MyCustomError]
  ```

  ### Rescue all exceptions

  ```
  plug Tesla.Middleware.Tuples, rescue_errors: :all
  ```
  """
  def call(env, next, opts) do
    {:ok, Tesla.run(env, next)}
  rescue
    ex in Tesla.Error ->
      {:error, ex}

    ex ->
      case opts[:rescue_errors] do
        nil ->
          reraise ex, System.stacktrace()

        :all ->
          {:error, ex}

        list ->
          if ex.__struct__ in list do
            {:error, ex}
          else
            reraise ex, System.stacktrace()
          end
      end
  end
end
