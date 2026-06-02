defmodule Tesla.Middleware.Compression do
  @moduledoc """
  Compress requests and decompress responses.

  Supports "gzip" and "deflate" encodings using Erlang's built-in `:zlib` module.

  ## Examples

  ```elixir
  defmodule MyClient do
    def client do
      Tesla.client([
        {Tesla.Middleware.Compression, format: "gzip", max_body_size: 32 * 1024 * 1024}
      ])
    end
  end
  ```

  ## Options

  - `:format` - request compression format, `"gzip"` (default) or `"deflate"`.
  - `:max_body_size` - **required.** Maximum size, in bytes, of any decompressed
    response body. Pass a positive integer (e.g. `32 * 1024 * 1024`) or `:infinity`
    to disable the cap explicitly. Responses that decompress to more bytes raise
    `Tesla.Middleware.Compression.Error` with reason `:max_body_size_exceeded`.

  ## Security

  Decompressing untrusted response bodies without a size cap is a denial-of-service
  vector ("zip bomb"): a small response can inflate into gigabytes of memory and
  exhaust the BEAM heap. To make that impossible by construction this middleware:

  - requires `:max_body_size` to be set so the cap is always a conscious choice;
  - streams inflation through `:zlib.safeInflate/2` and aborts as soon as the
    cap is exceeded, before the full body is materialised in memory; and
  - rejects responses that advertise more than one supported compression codec
    in `content-encoding`, since stacked codecs are almost exclusively a bomb
    pattern and cannot be safely bounded by a single per-layer cap.
  """

  @behaviour Tesla.Middleware

  defmodule Error do
    @moduledoc """
    Raised when a response cannot be safely decompressed.

    The `:reason` field is one of:

    - `:max_body_size_exceeded` - the decompressed body grew past the configured
      `:max_body_size`.
    - `:multiple_codecs` - the response advertised more than one supported
      `content-encoding` codec (e.g. `gzip, gzip`).
    - `{:zlib, term}` - the underlying `:zlib` stream returned an error.
    """

    defexception [:reason, :message]

    @impl true
    def exception(opts) do
      reason = Keyword.fetch!(opts, :reason)
      %__MODULE__{reason: reason, message: message_for(reason)}
    end

    defp message_for(:max_body_size_exceeded),
      do: "decompressed response body exceeds the configured :max_body_size"

    defp message_for(:multiple_codecs),
      do:
        "refusing to decompress response advertising more than one supported " <>
          "content-encoding codec (stacked codecs are a zip-bomb amplification vector)"

    defp message_for({:zlib, reason}),
      do: "zlib error during decompression: #{inspect(reason)}"
  end

  @impl Tesla.Middleware
  def call(env, next, opts) do
    env
    |> compress(opts)
    |> add_accept_encoding()
    |> Tesla.run(next)
    |> decompress(opts)
  end

  @doc false
  def add_accept_encoding(env) do
    Tesla.put_headers(env, [{"accept-encoding", "gzip, deflate, identity"}])
  end

  defp compressible?(body), do: is_binary(body)

  @doc """
  Compress request.

  It is used by `Tesla.Middleware.CompressRequest`.
  """
  def compress(env, opts) do
    if compressible?(env.body) do
      format = Keyword.get(opts || [], :format, "gzip")

      env
      |> Tesla.put_body(compress_body(env.body, format))
      |> Tesla.put_headers([{"content-encoding", format}])
    else
      env
    end
  end

  defp compress_body(body, "gzip"), do: :zlib.gzip(body)
  defp compress_body(body, "deflate"), do: :zlib.zip(body)

  @doc """
  Decompress response.

  It is used by `Tesla.Middleware.DecompressResponse`.
  """
  def decompress({:ok, env}, opts), do: {:ok, decompress(env, opts)}
  def decompress({:error, reason}, _opts), do: {:error, reason}

  # HEAD requests may be used to obtain information on the transfer size and properties
  # and their empty bodies are not actually valid for the possibly indicated encodings
  # thus we want to preserve them unchanged.
  def decompress(%Tesla.Env{method: :head} = env, _opts), do: env

  def decompress(env, opts) do
    max_body_size = fetch_max_body_size!(opts)
    codecs = compression_algorithms(Tesla.get_header(env, "content-encoding"))

    if count_known_codecs(codecs) > 1 do
      raise Error, reason: :multiple_codecs
    end

    {decompressed_body, unknown_codecs} = decompress_body(codecs, env.body, max_body_size)

    env
    |> put_decompressed_body(decompressed_body)
    |> put_or_delete_content_encoding(unknown_codecs)
  end

  defp fetch_max_body_size!(opts) do
    case Keyword.fetch(opts || [], :max_body_size) do
      {:ok, :infinity} ->
        :infinity

      {:ok, size} when is_integer(size) and size > 0 ->
        size

      {:ok, other} ->
        raise ArgumentError,
              "Tesla.Middleware.Compression :max_body_size must be a positive integer " <>
                "or :infinity, got: #{inspect(other)}"

      :error ->
        raise ArgumentError,
              "Tesla.Middleware.Compression requires the :max_body_size option to be set. " <>
                "Pass a positive integer cap (e.g. max_body_size: 32 * 1024 * 1024) " <>
                "or :infinity to opt out of the cap explicitly. " <>
                "See the moduledoc for the security rationale."
    end
  end

  defp count_known_codecs(codecs) do
    Enum.count(codecs, &(&1 in ["gzip", "x-gzip", "deflate"]))
  end

  defp put_or_delete_content_encoding(env, []) do
    Tesla.delete_header(env, "content-encoding")
  end

  defp put_or_delete_content_encoding(env, unknown_codecs) do
    Tesla.put_header(env, "content-encoding", Enum.join(unknown_codecs, ", "))
  end

  defp decompress_body([gzip | rest], body, max_body_size) when gzip in ["gzip", "x-gzip"] do
    decompress_body(rest, inflate(body, 31, max_body_size), max_body_size)
  end

  # `:zlib.unzip/1` (the original Tesla call) uses raw deflate with negative
  # window bits; `:zlib.zip/1` round-trips through that, so keep the same
  # framing here for backwards-compatible "deflate" responses.
  defp decompress_body(["deflate" | rest], body, max_body_size) do
    decompress_body(rest, inflate(body, -15, max_body_size), max_body_size)
  end

  defp decompress_body(["identity" | rest], body, max_body_size) do
    decompress_body(rest, body, max_body_size)
  end

  defp decompress_body([codec | rest], body, _max_body_size) do
    {body, Enum.reverse([codec | rest])}
  end

  defp decompress_body([], body, _max_body_size) do
    {body, []}
  end

  defp inflate(body, window_bits, max_body_size) do
    z = :zlib.open()

    try do
      :zlib.inflateInit(z, window_bits)
      result = start_inflate(z, body, max_body_size)
      # Verifies the stream was complete; raises :data_error for empty,
      # truncated, or otherwise invalid input the same way :zlib.gunzip/1 did.
      :zlib.inflateEnd(z)
      result
    catch
      :error, :data_error ->
        reraise Error, [reason: {:zlib, :data_error}], __STACKTRACE__

      :error, {:data_error, _} = reason ->
        reraise Error, [reason: {:zlib, reason}], __STACKTRACE__
    after
      :zlib.close(z)
    end
  end

  defp start_inflate(z, body, max_body_size) do
    case :zlib.safeInflate(z, body) do
      {:finished, output} ->
        size = IO.iodata_length(output)
        ensure_within_limit!(size, max_body_size)
        IO.iodata_to_binary(output)

      {:continue, output} ->
        size = IO.iodata_length(output)
        ensure_within_limit!(size, max_body_size)
        drain_inflate(z, max_body_size, size, [output])
    end
  end

  defp drain_inflate(z, max_body_size, total_size, acc) do
    case :zlib.safeInflate(z, []) do
      {:continue, output} ->
        new_total = total_size + IO.iodata_length(output)
        ensure_within_limit!(new_total, max_body_size)
        drain_inflate(z, max_body_size, new_total, [acc, output])

      {:finished, output} ->
        new_total = total_size + IO.iodata_length(output)
        ensure_within_limit!(new_total, max_body_size)
        IO.iodata_to_binary([acc, output])
    end
  end

  defp ensure_within_limit!(_size, :infinity), do: :ok
  defp ensure_within_limit!(size, max) when size <= max, do: :ok

  defp ensure_within_limit!(_size, _max) do
    raise Error, reason: :max_body_size_exceeded
  end

  defp compression_algorithms(nil) do
    []
  end

  defp compression_algorithms(value) do
    value
    |> String.downcase()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reverse()
  end

  defp put_decompressed_body(env, body) do
    env
    |> Tesla.put_body(body)
    |> update_content_length(body)
  end

  # The value of the content-length header wil be inaccurate after decompression.
  # But setting it is mandatory or strongly encouraged in HTTP/1.0 and HTTP/1.1.
  # Except, when transfer-encoding is used defining content-length is invalid.
  # Thus we can neither just drop it nor indiscriminately add it, but will update it if it already exist.
  # Furthermore, content-length is technically allowed to be specified mutliple times if all values match,
  # to ensure consistency we must therefore make sure to drop any duplicate definitions while updating.
  defp update_content_length(env, body) when is_binary(body) do
    if Tesla.get_header(env, "content-length") != nil do
      env
      |> Tesla.delete_header("content-length")
      |> Tesla.put_header("content-length", "#{byte_size(body)}")
    else
      env
    end
  end

  defp update_content_length(env, _) do
    env
  end
end

defmodule Tesla.Middleware.CompressRequest do
  @moduledoc """
  Only compress request.

  See `Tesla.Middleware.Compression` for options.
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    env
    |> Tesla.Middleware.Compression.compress(opts)
    |> Tesla.run(next)
  end
end

defmodule Tesla.Middleware.DecompressResponse do
  @moduledoc """
  Only decompress response.

  See `Tesla.Middleware.Compression` for options. The `:max_body_size` option is
  **required**; see that module's "Security" section for the rationale.
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    env
    |> Tesla.Middleware.Compression.add_accept_encoding()
    |> Tesla.run(next)
    |> Tesla.Middleware.Compression.decompress(opts)
  end
end
