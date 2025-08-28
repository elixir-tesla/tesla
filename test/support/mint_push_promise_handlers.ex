defmodule Tesla.TestSupport.MintPushPromiseIndexHandler do
  def init(req, state) do
    :ok = :cowboy_req.push("/style.css", %{}, req)
    req = :cowboy_req.reply(200, %{"content-type" => "text/plain"}, "original response", req)
    {:ok, req, state}
  end
end

defmodule Tesla.TestSupport.MintPushPromiseStyleHandler do
  def init(req, state) do
    req = :cowboy_req.reply(200, %{"content-type" => "text/css"}, "body { color: red; }", req)
    {:ok, req, state}
  end
end
