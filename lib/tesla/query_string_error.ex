defmodule Tesla.QueryStringError do
  @moduledoc """
  Raised when a whole `Tesla.QueryString` cannot own the request query string.
  """

  defexception [:reason, :query, :url, :value, :details]

  @type reason ::
          :empty_content_type
          | :existing_query_string
          | :invalid_content_type
          | :invalid_options
          | :invalid_query_string
          | :leading_query_delimiter
          | :mixed_query_params
  @type t :: %__MODULE__{
          reason: reason(),
          query: term(),
          value: term(),
          details: String.t() | nil,
          url: String.t() | nil
        }

  def message(%__MODULE__{reason: :existing_query_string} = _value) do
    "cannot append #{inspect(Tesla.QueryString)} to a URL that already contains a query string"
  end

  def message(%__MODULE__{reason: :mixed_query_params} = value) do
    "cannot merge #{inspect(Tesla.QueryString)} with normal query params; got #{inspect(value.query)}"
  end

  def message(%__MODULE__{reason: :leading_query_delimiter} = value) do
    "expected query string not to include a leading ?; got #{inspect(value.value)}"
  end

  def message(%__MODULE__{reason: :invalid_query_string} = value) do
    "expected query string to be a string; got #{inspect(value.value)}"
  end

  def message(%__MODULE__{reason: :empty_content_type} = _value) do
    "expected query string content type to be a non-empty string"
  end

  def message(%__MODULE__{reason: :invalid_content_type} = value) do
    "expected query string content type to be a string; got #{inspect(value.value)}"
  end

  def message(%__MODULE__{reason: :invalid_options} = value) do
    "invalid query string options: #{value.details}"
  end
end
