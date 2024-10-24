defmodule Tesla.Adapter do
  @moduledoc """
  The adapter specification.

  Adapter is a module that denormalize request data stored in `Tesla.Env` in order to make
  request with lower level http client (e.g. `:httpc` or `:hackney`) and normalize response data
  in order to store it back to `Tesla.Env`. It has to implement `c:Tesla.Adapter.call/2`.

  ## Writing custom adapter

  Create a module implementing `c:Tesla.Adapter.call/2`.

  See `c:Tesla.Adapter.call/2` for details.

  ### Examples

      defmodule MyProject.CustomAdapter do
        alias Tesla.Multipart

        @behaviour Tesla.Adapter

        @override_defaults [follow_redirect: false]

        @impl Tesla.Adapter
        def call(env, opts) do
          opts = Tesla.Adapter.opts(@override_defaults, env, opts)

          with {:ok, {status, headers, body}} <- request(env.method, env.body, env.headers, opts) do
            {:ok, normalize_response(env, status, headers, body)}
          end
        end

        defp request(_method, %Stream{}, _headers, _opts) do
          {:error, "stream not supported by adapter"}
        end

        defp request(_method, %Multipart{}, _headers, _opts) do
          {:error, "multipart not supported by adapter"}
        end

        defp request(method, body, headers, opts) do
          :lower_level_http.request(method, body, denormalize_headers(headers), opts)
        end

        defp denormalize_headers(headers), do: ...
        defp normalize_response(env, status, headers, body), do: %Tesla.Env{env | ...}
      end

  """

  @typedoc """
  Unstructured data passed to the adapter using `opts[:adapter]`.
  """
  @type options :: any()

  @doc """
  Invoked when a request runs.

  ## Arguments

  - `env` - `t:Tesla.Env.t/0` struct that stores request/response data.
  - `options` - middleware options provided by user.
  """
  @callback call(env :: Tesla.Env.t(), options :: options()) :: Tesla.Env.result()

  @doc """
  Helper function that merges all adapter options.

  ## Arguments

  - `defaults` (optional) - useful to override lower level http client default
    configuration.
  - `env` - `t:Tesla.Env.t()`
  - `opts` - options provided to the adapter from `Tesla.client/2`.

  ## Precedence rules

  The options are merged in the following order of precedence (highest to lowest):

  1. Options from `env.opts[:adapter]` (highest precedence).
  2. Options provided to the adapter from `Tesla.client/2`.
  3. Default options (lowest precedence).

  This means that options specified in `env.opts[:adapter]` will override any
  conflicting options from the other sources, allowing for fine-grained control
  on a per-request basis.
  """
  @spec opts(Keyword.t(), Tesla.Env.t(), Keyword.t()) :: Keyword.t()
  def opts(defaults \\ [], env, opts) do
    defaults
    |> Keyword.merge(opts || [])
    |> Keyword.merge(env.opts[:adapter] || [])
  end
end
