defmodule Tesla.Multipart do
  @moduledoc """
  Multipart functionality.

  ## Examples

  ```
  mp =
    Multipart.new()
    |> Multipart.add_content_type_param("charset=utf-8")
    |> Multipart.add_field("field1", "foo")
    |> Multipart.add_field("field2", "bar",
      headers: [{"content-id", "1"}, {"content-type", "text/plain"}]
    )
    |> Multipart.add_file("test/tesla/multipart_test_file.sh")
    |> Multipart.add_file("test/tesla/multipart_test_file.sh", name: "foobar")
    |> Multipart.add_file_content("sample file content", "sample.txt")

  response = client.post(url, mp)
  ```
  """

  defmodule Part do
    defstruct body: nil,
              dispositions: [],
              headers: []

    @type t :: %__MODULE__{
            body: String.t(),
            headers: Tesla.Env.headers(),
            dispositions: Keyword.t()
          }
  end

  @type part_stream :: Enum.t()
  @type part_value :: iodata | part_stream | function()

  @token_specials ~c"!#$%&'*+-.^_`|~"

  defguardp is_tchar(c)
            when c in ?A..?Z or
                   c in ?a..?z or
                   c in ?0..?9 or
                   c in @token_specials

  defguardp is_field_vchar(c) when c == ?\t or (c >= 32 and c != 127)

  defguardp is_qdtext(c)
            when (c == ?\t or (c >= 32 and c != 127)) and c != ?" and c != ?\\

  defstruct parts: [],
            boundary: nil,
            content_type_params: []

  @type t :: %__MODULE__{
          parts: list(Tesla.Multipart.Part.t()),
          boundary: String.t(),
          content_type_params: [String.t()]
        }

  @doc """
  Create a new Multipart struct to be used for a request body.
  """
  @spec new() :: t
  def new do
    %__MODULE__{boundary: unique_string()}
  end

  @doc """
  Add a parameter to the multipart content-type.

  Raises `ArgumentError` if `param` contains characters that are not
  allowed in an HTTP `Content-Type` parameter per RFC 7231 §3.1.1.1,
  preventing header injection into the outgoing `Content-Type` header.
  """
  @spec add_content_type_param(t, String.t()) :: t
  def add_content_type_param(%__MODULE__{} = mp, param) do
    :ok = assert_content_type_param!(param)
    %{mp | content_type_params: mp.content_type_params ++ [param]}
  end

  @doc """
  Add a field part.
  """
  @spec add_field(t, String.t(), part_value, Keyword.t()) :: t | no_return
  def add_field(%__MODULE__{} = mp, name, value, opts \\ []) do
    :ok = assert_part_value!(value)
    :ok = assert_quoted_string_safe!("field name", name)
    {headers, opts} = Keyword.pop_first(opts, :headers, [])
    :ok = assert_part_headers!(headers)
    :ok = assert_dispositions!(opts)

    part = %Part{
      body: value,
      headers: headers,
      dispositions: [{:name, name}] ++ opts
    }

    %{mp | parts: mp.parts ++ [part]}
  end

  @doc """
  Add a file part. The file will be streamed.

  ## Options

  - `:name` - name of form param
  - `:filename` - filename (defaults to path basename)
  - `:headers` - additional headers
  - `:detect_content_type` - auto-detect file content-type (defaults to false)
  """
  @spec add_file(t, String.t(), Keyword.t()) :: t
  def add_file(%__MODULE__{} = mp, path, opts \\ []) do
    {filename, opts} = Keyword.pop_first(opts, :filename, Path.basename(path))
    {headers, opts} = Keyword.pop_first(opts, :headers, [])
    {detect_content_type, opts} = Keyword.pop_first(opts, :detect_content_type, false)

    # add in detected content-type if necessary
    headers =
      case detect_content_type do
        true -> List.keystore(headers, "content-type", 0, {"content-type", MIME.from_path(path)})
        false -> headers
      end

    data = stream_file!(path, 2048)
    add_file_content(mp, data, filename, opts ++ [headers: headers])
  end

  @doc """
  Add a file part with value.

  Same as `add_file/3` but the file content is read from `data` input argument.

  ## Options

  - `:name` - name of form param
  - `:headers` - additional headers
  """
  @spec add_file_content(t, part_value, String.t(), Keyword.t()) :: t
  def add_file_content(%__MODULE__{} = mp, data, filename, opts \\ []) do
    {name, opts} = Keyword.pop_first(opts, :name, "file")
    add_field(mp, name, data, opts ++ [filename: filename])
  end

  @doc false
  @spec headers(t) :: Tesla.Env.headers()
  def headers(%__MODULE__{boundary: boundary, content_type_params: params}) do
    ct_params = (["boundary=#{boundary}"] ++ params) |> Enum.join("; ")
    [{"content-type", "multipart/form-data; #{ct_params}"}]
  end

  @doc false
  @spec body(t) :: part_stream
  def body(%__MODULE__{boundary: boundary, parts: parts}) do
    part_streams = Enum.map(parts, &part_as_stream(&1, boundary))
    Stream.concat(part_streams ++ [["--#{boundary}--\r\n"]])
  end

  @doc false
  @spec part_as_stream(Part.t(), String.t()) :: part_stream
  def part_as_stream(
        %Part{body: body, dispositions: dispositions, headers: part_headers},
        boundary
      ) do
    part_headers = Enum.map(part_headers, fn {k, v} -> "#{k}: #{v}\r\n" end)
    part_headers = part_headers ++ [part_headers_for_disposition(dispositions)]

    enum_body =
      case body do
        b when is_binary(b) -> [b]
        b -> b
      end

    Stream.concat([
      ["--#{boundary}\r\n"],
      part_headers,
      ["\r\n"],
      enum_body,
      ["\r\n"]
    ])
  end

  @doc false
  @spec part_headers_for_disposition(Keyword.t()) :: [String.t()]
  def part_headers_for_disposition([]), do: []

  def part_headers_for_disposition(kvs) do
    ds =
      kvs
      |> Enum.map(fn {k, v} ->
        v_str = to_string(v)
        :ok = assert_disposition_value!(k, v_str)
        "#{k}=\"#{v_str}\""
      end)
      |> Enum.join("; ")

    ["content-disposition: form-data; #{ds}\r\n"]
  end

  @spec assert_disposition_value!(atom | String.t(), String.t()) :: :ok | no_return
  defp assert_disposition_value!(key, value) do
    cond do
      String.contains?(value, ["\r", "\n"]) ->
        raise ArgumentError,
              "invalid multipart content-disposition value for #{inspect(key)}: " <>
                "must not contain CR or LF characters"

      String.contains?(value, "\"") ->
        raise ArgumentError,
              "invalid multipart content-disposition value for #{inspect(key)}: " <>
                "must not contain double-quote characters"

      true ->
        :ok
    end
  end

  @spec unique_string() :: String.t()
  defp unique_string() do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  @spec assert_part_value!(any) :: :ok | no_return
  defp assert_part_value!(%maybe_stream{})
       when maybe_stream in [IO.Stream, File.Stream, Stream, Range],
       do: :ok

  defp assert_part_value!(value)
       when is_list(value)
       when is_binary(value)
       when is_function(value),
       do: :ok

  defp assert_part_value!(val) do
    raise(ArgumentError, "#{inspect(val)} is not a supported multipart value.")
  end

  @spec assert_part_headers!(Tesla.Env.headers()) :: :ok | no_return
  defp assert_part_headers!(headers) when is_list(headers) do
    Enum.each(headers, &assert_part_header!/1)
  end

  defp assert_part_header!({name, value}) do
    :ok = assert_token!("header name", to_string(name))
    :ok = assert_field_value!("header value", to_string(value))
  end

  @spec assert_dispositions!(Keyword.t()) :: :ok | no_return
  defp assert_dispositions!(dispositions) when is_list(dispositions) do
    Enum.each(dispositions, &assert_disposition!/1)
  end

  defp assert_disposition!({_key, value}) do
    assert_quoted_string_safe!("disposition value", to_string(value))
  end

  @spec assert_token!(String.t(), any) :: :ok | no_return
  defp assert_token!(label, <<c, _::binary>> = value) when is_tchar(c) do
    do_assert_token!(label, value, value)
  end

  defp assert_token!(label, value) do
    raise ArgumentError,
          "#{label} must be a non-empty RFC 7230 token, got: #{inspect(value)}"
  end

  defp do_assert_token!(_label, _orig, <<>>), do: :ok

  defp do_assert_token!(label, orig, <<c, rest::binary>>) when is_tchar(c) do
    do_assert_token!(label, orig, rest)
  end

  defp do_assert_token!(label, orig, <<c, _::binary>>) do
    raise ArgumentError,
          "#{label} must be an RFC 7230 token, got: #{inspect(orig)} " <>
            "(invalid character: #{inspect(<<c>>)})"
  end

  @spec assert_field_value!(String.t(), any) :: :ok | no_return
  defp assert_field_value!(label, value) when is_binary(value) do
    do_assert_field_value!(label, value, value)
  end

  defp do_assert_field_value!(_label, _orig, <<>>), do: :ok

  defp do_assert_field_value!(label, orig, <<c, rest::binary>>) when is_field_vchar(c) do
    do_assert_field_value!(label, orig, rest)
  end

  defp do_assert_field_value!(label, orig, <<c, _::binary>>) do
    raise ArgumentError,
          "#{label} must contain only printable characters per RFC 7230 " <>
            "(no CTLs other than HTAB, no DEL), got: #{inspect(orig)} " <>
            "(invalid character: #{inspect(<<c>>)})"
  end

  @spec assert_quoted_string_safe!(String.t(), any) :: :ok | no_return
  defp assert_quoted_string_safe!(label, value) when is_binary(value) do
    do_assert_quoted_string_safe!(label, value, value)
  end

  defp do_assert_quoted_string_safe!(_label, _orig, <<>>), do: :ok

  defp do_assert_quoted_string_safe!(label, orig, <<c, rest::binary>>) when is_qdtext(c) do
    do_assert_quoted_string_safe!(label, orig, rest)
  end

  defp do_assert_quoted_string_safe!(label, orig, <<c, _::binary>>) do
    raise ArgumentError,
          "#{label} must be safe for an HTTP quoted-string per RFC 7230 " <>
            "(no CTLs other than HTAB, no DEL, no `\"`, no `\\`), got: " <>
            "#{inspect(orig)} (invalid character: #{inspect(<<c>>)})"
  end

  @spec assert_content_type_param!(any) :: :ok | no_return
  defp assert_content_type_param!(value) when is_binary(value) and byte_size(value) > 0 do
    do_assert_ctp!(value, value)
  end

  defp assert_content_type_param!(value) do
    raise ArgumentError,
          "content-type param must be a non-empty string, got: #{inspect(value)}"
  end

  defp do_assert_ctp!(_orig, <<>>), do: :ok

  defp do_assert_ctp!(orig, <<c, rest::binary>>) when is_field_vchar(c) and c != ?; do
    do_assert_ctp!(orig, rest)
  end

  defp do_assert_ctp!(orig, <<c, _::binary>>) do
    raise ArgumentError,
          "content-type param must not contain CTLs, DEL, or `;` per RFC 7231, " <>
            "got: #{inspect(orig)} (invalid character: #{inspect(<<c>>)})"
  end

  if Version.compare(System.version(), "1.16.0") in [:gt, :eq] do
    defp stream_file!(path, bytes), do: File.stream!(path, bytes)
  else
    defp stream_file!(path, bytes), do: File.stream!(path, [], bytes)
  end
end
