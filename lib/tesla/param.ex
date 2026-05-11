defmodule Tesla.Param do
  @moduledoc false

  @query_reserved ~c":/?#[]@!$&'()*+,;="
  @path_reserved [?!, ?$, ?&, ?', ?(, ?), ?*, ?+, ?,, ?;, ?=, ?:, ?@]

  def validate_name!(_kind, name) when is_binary(name) do
    name
  end

  def validate_name!(kind, name) do
    raise ArgumentError, "expected #{kind} parameter name to be a string; got #{inspect(name)}"
  end

  def validate_opts!(_kind, opts) when is_list(opts) do
    opts
  end

  def validate_opts!(kind, opts) do
    raise ArgumentError,
          "expected #{kind} parameter options to be a keyword list; got #{inspect(opts)}"
  end

  def validate_style!(style, styles, kind, expected) do
    case style in styles do
      true ->
        style

      false ->
        raise ArgumentError,
              "unknown #{kind} parameter style #{inspect(style)}; expected #{expected}"
    end
  end

  def validate_explode!(kind, value) do
    validate_option_boolean!(kind, :explode, value)
  end

  def validate_allow_reserved!(kind, value) do
    validate_option_boolean!(kind, :allow_reserved, value)
  end

  defp validate_option_boolean!(_kind, _key, value) when is_boolean(value) do
    value
  end

  defp validate_option_boolean!(:path, key, value) do
    raise ArgumentError, "expected #{inspect(key)} to be a boolean; got #{inspect(value)}"
  end

  defp validate_option_boolean!(kind, key, value) do
    raise ArgumentError,
          "expected #{kind} parameter #{inspect(key)} to be a boolean; got #{inspect(value)}"
  end

  def classify_value(nil) do
    :undefined
  end

  def classify_value(value) when is_struct(value) do
    value
    |> Map.from_struct()
    |> classify_value()
  end

  def classify_value(value) when is_map(value) do
    {:object, value |> Map.to_list() |> Enum.map(&stringify_pair/1)}
  end

  def classify_value([]) do
    {:array, []}
  end

  def classify_value(value) when is_list(value) do
    case Enum.all?(value, &object_pair?/1) do
      true -> {:object, Enum.map(value, &stringify_pair/1)}
      false -> {:array, value}
    end
  end

  def classify_value(value) do
    {:primitive, value}
  end

  def flatten_pairs(pairs) do
    Enum.flat_map(pairs, &pair_values/1)
  end

  def encode_unreserved(value) do
    value
    |> to_string()
    |> URI.encode(&unreserved?/1)
  end

  def encode_reserved_query(value) do
    value
    |> to_string()
    |> encode_reserved(&query_reserved?/1)
  end

  def encode_reserved_path(value) do
    value
    |> to_string()
    |> encode_reserved(&path_reserved?/1)
  end

  defp stringify_pair({key, value}) do
    {to_string(key), value}
  end

  defp object_pair?({key, _value}) when is_atom(key) or is_binary(key) do
    true
  end

  defp object_pair?(_value) do
    false
  end

  defp pair_values({key, value}) do
    [key, value]
  end

  defp encode_reserved(<<>>, _allowed?) do
    ""
  end

  defp encode_reserved(<<"%", high, low, rest::binary>>, allowed?) do
    case hex?(high) and hex?(low) do
      true ->
        "%" <> <<high, low>> <> encode_reserved(rest, allowed?)

      false ->
        "%25" <> encode_reserved(<<high, low, rest::binary>>, allowed?)
    end
  end

  defp encode_reserved(<<"%", rest::binary>>, allowed?) do
    "%25" <> encode_reserved(rest, allowed?)
  end

  defp encode_reserved(<<byte, rest::binary>>, allowed?) do
    case allowed?.(byte) do
      true ->
        <<byte>> <> encode_reserved(rest, allowed?)

      false ->
        percent_encode_byte(byte) <> encode_reserved(rest, allowed?)
    end
  end

  defp percent_encode_byte(byte) do
    "%" <> Base.encode16(<<byte>>)
  end

  defp hex?(byte) when byte in ?0..?9 do
    true
  end

  defp hex?(byte) when byte in ?A..?F do
    true
  end

  defp hex?(byte) when byte in ?a..?f do
    true
  end

  defp hex?(_byte) do
    false
  end

  defp query_reserved?(byte) do
    unreserved?(byte) or byte in @query_reserved
  end

  defp path_reserved?(byte) do
    unreserved?(byte) or byte in @path_reserved
  end

  defp unreserved?(byte) when byte in ?A..?Z do
    true
  end

  defp unreserved?(byte) when byte in ?a..?z do
    true
  end

  defp unreserved?(byte) when byte in ?0..?9 do
    true
  end

  defp unreserved?(byte) when byte in [?-, ?_, ?., ?~] do
    true
  end

  defp unreserved?(_byte) do
    false
  end
end
