defmodule Tesla.QueryString do
  @moduledoc """
  A whole URL query string with explicit serialization.

  `Tesla.QueryString` is a Tesla-native value object for requests where the
  entire query string is serialized as one value. It is useful for OpenAPI 3.2
  [`in: "querystring"` parameters][oas-parameter-locations], where the query
  string is content-based and does not behave like a normal named query
  parameter.

  Pass a query string value directly as the request `:query`:

      alias Tesla.QueryString

      Tesla.get(client, "/search",
        query: QueryString.form!(foo: "a + b", bar: true)
      )

  The encoded query string is resolved before the adapter sends the request.

  ## Constructors

    * `raw!/2` - accepts an already-serialized query string, without the leading
      `?`.
    * `form!/1` - serializes structured params as
      `application/x-www-form-urlencoded` using Tesla's default query encoder.

  [oas-parameter-locations]: https://spec.openapis.org/oas/latest.html#parameter-locations
  """

  alias Tesla.QueryStringError

  @derive {Inspect, except: [:encoded]}
  @enforce_keys [:encoded, :content_type]
  defstruct [:encoded, :content_type]

  @type content_type :: String.t()
  @opaque t :: %__MODULE__{
            encoded: String.t(),
            content_type: content_type()
          }

  @form_content_type "application/x-www-form-urlencoded"

  @spec raw!(String.t(), keyword()) :: t()
  def raw!(encoded, opts \\ []) do
    opts = validate_options!(opts)

    %__MODULE__{
      encoded: validate_encoded!(encoded),
      content_type: validate_content_type!(opts[:content_type])
    }
  end

  @spec form!(Tesla.Env.query()) :: t()
  def form!(params) do
    %__MODULE__{
      encoded: Tesla.encode_query(params),
      content_type: @form_content_type
    }
  end

  @doc false
  @spec append_to_url(%__MODULE__{}, Tesla.Env.url()) :: Tesla.Env.url()
  def append_to_url(%__MODULE__{} = query_string, url) do
    case :binary.match(url, ["?", "#"]) do
      {index, 1} ->
        append_after_marker(url, query_string, index)

      :nomatch ->
        append_query(url, query_string)
    end
  end

  @doc false
  @spec to_query(%__MODULE__{}) :: String.t()
  def to_query(%__MODULE__{encoded: encoded}) do
    encoded
  end

  defp append_after_marker(url, query_string, index) do
    case :binary.at(url, index) do
      ?? ->
        raise QueryStringError, reason: :existing_query_string, url: url

      ?# ->
        append_query_before_fragment(url, query_string, index)
    end
  end

  defp append_query_before_fragment(url, %__MODULE__{encoded: ""}, _fragment_index) do
    url
  end

  defp append_query_before_fragment(url, query_string, fragment_index) do
    base = binary_part(url, 0, fragment_index)
    fragment = binary_part(url, fragment_index, byte_size(url) - fragment_index)

    base <> "?" <> to_query(query_string) <> fragment
  end

  defp append_query(url, %__MODULE__{encoded: ""}) do
    url
  end

  defp append_query(url, query_string) do
    url <> "?" <> to_query(query_string)
  end

  defp validate_options!(opts) do
    Keyword.validate!(opts, content_type: @form_content_type)
  rescue
    error in [ArgumentError, FunctionClauseError] ->
      raise QueryStringError,
        reason: :invalid_options,
        value: opts,
        details: Exception.message(error)
  end

  defp validate_encoded!(encoded) when is_binary(encoded) do
    case String.starts_with?(encoded, "?") do
      true ->
        raise QueryStringError, reason: :leading_query_delimiter, value: encoded

      false ->
        encoded
    end
  end

  defp validate_encoded!(encoded) do
    raise QueryStringError, reason: :invalid_query_string, value: encoded
  end

  defp validate_content_type!(content_type) when is_binary(content_type) do
    case content_type do
      "" ->
        raise QueryStringError, reason: :empty_content_type, value: content_type

      content_type ->
        content_type
    end
  end

  defp validate_content_type!(content_type) do
    raise QueryStringError, reason: :invalid_content_type, value: content_type
  end
end
