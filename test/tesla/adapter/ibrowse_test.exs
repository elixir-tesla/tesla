defmodule Tesla.Adapter.IbrowseTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Ibrowse

  @http "http://0.0.0.0:#{Application.get_env(:httparrot, :http_port)}"
  @https "https://0.0.0.0:#{Application.get_env(:httparrot, :https_port)}"

  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody
  use Tesla.AdapterCase.SSL
end
