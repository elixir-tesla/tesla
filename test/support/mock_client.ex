defmodule MockClient do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "http://example.com"
  plug Tesla.Middleware.JSON

  def list do
    get("/list")
  end

  def search() do
    get("/search")
  end

  def create(data) do
    post("/create", data)
  end
end
