defmodule Tesla.TestSupport.MintEarlyResponseHandler do
  def init(req, state) do
    req = :cowboy_req.reply(200, %{"content-type" => "text/plain"}, "early response", req)
    {:ok, req, state}
  end
end
