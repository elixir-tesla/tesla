defmodule Tesla.Middleware.BaseUrl do
  @moduledoc """
  Set base URL for all requests.

  By default, the base URL will be prepended to request path/URL only
  if it does not include http(s). Use the `policy: :strict` option to
  enforce base URL prepending regardless of scheme presence.

  ## Options

  The options can be passed as a keyword list or a string representing the base URL.

  - `:base_url` - The base URL to use for all requests.
  - `:policy` - Can be set to `:strict` to enforce base URL prepending even when
    the request URL already includes a scheme. Useful for security when the URL is
    controlled by user input. Defaults to `:insecure`.

  > ### Security Considerations {: .warning}
  > When URLs are controlled by user input, always use `policy: :strict` to prevent
  > URL redirection attacks. The default `:insecure` policy allows users to bypass
  > the base URL by providing fully qualified URLs.

  ## Examples

  ```elixir
  defmodule MyClient do
    def client do
      Tesla.client([
        # Using keyword format (recommended)
        {Tesla.Middleware.BaseUrl, base_url: "https://example.com/foo"}
        # or alternatively, using string
        # {Tesla.Middleware.BaseUrl, "https://example.com/foo"}
      ])
    end
  end

  client = MyClient.client()

  Tesla.get(client, "/path")
  # equals to GET https://example.com/foo/path

  Tesla.get(client, "path")
  # equals to GET https://example.com/foo/path

  Tesla.get(client, "")
  # equals to GET https://example.com/foo

  Tesla.get(client, "http://example.com/bar")
  # equals to GET http://example.com/bar (scheme detected, base URL not prepended)

  # Using strict policy for user-controlled URLs (security)
  defmodule MySecureClient do
    def client do
      Tesla.client([
        {Tesla.Middleware.BaseUrl, base_url: "https://example.com/foo", policy: :strict}
      ])
    end
  end

  secure_client = MySecureClient.client()

  Tesla.get(secure_client, "http://example.com/bar")
  # equals to GET https://example.com/foo/http://example.com/bar (base URL always prepended)

  Tesla.get(secure_client, "/safe/path")
  # equals to GET https://example.com/foo/safe/path
  ```
  """

  @behaviour Tesla.Middleware

  @type policy :: :strict | :insecure
  @type opts :: [base_url: String.t(), policy: policy] | String.t()

  @impl Tesla.Middleware
  @spec call(Tesla.Env.t(), Tesla.Env.stack(), opts()) :: Tesla.Env.result()
  def call(env, next, opts) do
    {base_url, opts} = parse_opts!(opts)

    env
    |> apply_base(base_url, opts)
    |> Tesla.run(next)
  end

  defp parse_opts!(opts) when is_binary(opts) do
    {opts, []}
  end

  defp parse_opts!(opts) when is_list(opts) do
    case Keyword.pop(opts, :base_url) do
      {base_url, remaining_opts} when is_binary(base_url) ->
        {base_url, remaining_opts}

      {base_url, _remaining_opts} ->
        raise ArgumentError, "base_url must be a string but got #{inspect(base_url)}"
    end
  end

  defp apply_base(env, base_url, opts) do
    case get_policy!(opts) do
      :strict ->
        %{env | url: join(base_url, env.url)}

      :insecure ->
        if Regex.match?(~r/^https?:\/\//i, env.url) do
          env
        else
          %{env | url: join(base_url, env.url)}
        end
    end
  end

  defp get_policy!(opts) do
    case Keyword.get(opts, :policy, :insecure) do
      policy when policy in [:strict, :insecure] ->
        policy

      other ->
        raise ArgumentError, "invalid policy #{inspect(other)}, expected :strict or :insecure"
    end
  end

  defp join(base, url) do
    case {String.last(to_string(base)), url} do
      {nil, url} -> url
      {"/", "/" <> rest} -> base <> rest
      {"/", rest} -> base <> rest
      {_, ""} -> base
      {_, "/" <> rest} -> base <> "/" <> rest
      {_, rest} -> base <> "/" <> rest
    end
  end
end
