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
    @moduledoc false

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
  @type part_value :: iodata | part_stream

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
  """
  @spec add_content_type_param(t, String.t()) :: t
  def add_content_type_param(%__MODULE__{} = mp, param) do
    %{mp | content_type_params: mp.content_type_params ++ [param]}
  end

  @doc """
  Add a field part.
  """
  @spec add_field(t, String.t(), part_value, Keyword.t()) :: t | no_return
  def add_field(%__MODULE__{} = mp, name, value, opts \\ []) do
    :ok = assert_part_value!(value)
    {headers, opts} = Keyword.pop_first(opts, :headers, [])

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

    data = File.stream!(path, [], 2048)
    add_file_content(mp, data, filename, opts ++ [headers: headers])
  end

  @doc """
  Add a file part with value.

  Same of `add_file/3` but the file content is read from `data` input argument.

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
      |> Enum.map(fn {k, v} -> "#{k}=\"#{v}\"" end)
      |> Enum.join("; ")

    ["content-disposition: form-data; #{ds}\r\n"]
  end

  @spec unique_string() :: String.t()
  defp unique_string() do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  @spec assert_part_value!(any) :: :ok | no_return
  defp assert_part_value!(%maybe_stream{})
       when maybe_stream in [IO.Stream, File.Stream, Stream],
       do: :ok

  defp assert_part_value!(value)
       when is_list(value)
       when is_binary(value),
       do: :ok

  defp assert_part_value!(val) do
    raise(ArgumentError, "#{inspect(val)} is not a supported multipart value.")
  end
end
