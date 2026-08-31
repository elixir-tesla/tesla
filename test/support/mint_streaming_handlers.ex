defmodule Tesla.TestSupport.MintStalledBodyHandler do
  @moduledoc """
  Replies with headers and then never sends a body, so the client is left
  waiting mid-response.
  """

  def init(req, state) do
    req = :cowboy_req.stream_reply(200, %{"content-type" => "text/plain"}, req)
    Process.sleep(60_000)
    {:ok, req, state}
  end
end

defmodule Tesla.TestSupport.MintTrailersHandler do
  @moduledoc """
  Replies with a chunked body followed by trailers.
  """

  def init(req, state) do
    req =
      :cowboy_req.stream_reply(
        200,
        %{"content-type" => "text/plain", "trailer" => "x-checksum"},
        req
      )

    :cowboy_req.stream_body("hello", :nofin, req)
    :cowboy_req.stream_trailers(%{"x-checksum" => "abc"}, req)
    {:ok, req, state}
  end
end

defmodule Tesla.TestSupport.MintChunkedBodyHandler do
  @moduledoc """
  Replies with a body split into many chunks, so it spans several packets.
  """

  def init(req, state) do
    req = :cowboy_req.stream_reply(200, %{"content-type" => "text/plain"}, req)

    Enum.each(1..200, fn _ -> :cowboy_req.stream_body("chunk", :nofin, req) end)

    :cowboy_req.stream_body("", :fin, req)
    {:ok, req, state}
  end
end
