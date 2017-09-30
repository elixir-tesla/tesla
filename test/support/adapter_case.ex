defmodule Tesla.AdapterCase do
  @http_url   "http://localhost:#{Application.get_env(:httparrot, :http_port)}"
  @https_url  "https://httpbin.org"

  def http_url,   do: @http_url
  def https_url,  do: @https_url
end
