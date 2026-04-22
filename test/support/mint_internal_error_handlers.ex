defmodule Tesla.TestSupport.MintInternalErrorRequestHandler do
  def init(req, state) do
    receive do
    after
      50 -> {:ok, req, state}
    end
  end
end

defmodule Tesla.TestSupport.MintInternalErrorAfterHeadersRequestHandler do
  def init(req, _state) do
    :cowboy_req.stream_reply(200, %{"content-type" => "text/plain"}, req)
    raise "issue 553 after headers"
  end
end

defmodule Tesla.TestSupport.MintInternalErrorStreamHandler do
  @behaviour :cowboy_stream

  def init(stream_id, req, opts) do
    {commands, state} = :cowboy_stream.init(stream_id, req, opts)

    if :cowboy_req.path(req) == "/stream-reset" do
      {commands ++ [{:internal_error, :issue_553, ~c"Issue 553 reproduction"}], state}
    else
      {commands, state}
    end
  end

  def data(stream_id, is_fin, data, state) do
    :cowboy_stream.data(stream_id, is_fin, data, state)
  end

  def info(stream_id, info, state) do
    :cowboy_stream.info(stream_id, info, state)
  end

  def terminate(stream_id, reason, state) do
    :cowboy_stream.terminate(stream_id, reason, state)
  end

  def early_error(stream_id, reason, partial_req, resp, opts) do
    :cowboy_stream.early_error(stream_id, reason, partial_req, resp, opts)
  end
end
