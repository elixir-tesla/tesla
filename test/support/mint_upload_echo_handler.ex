defmodule Tesla.TestSupport.MintUploadEchoHandler do
  def init(req, state) do
    {body_length, req} = read_body_length(req, 0)

    req =
      :cowboy_req.reply(
        200,
        %{"content-type" => "text/plain"},
        Integer.to_string(body_length),
        req
      )

    {:ok, req, state}
  end

  defp read_body_length(req, length) do
    case :cowboy_req.read_body(req) do
      {:ok, data, req} -> {length + byte_size(data), req}
      {:more, data, req} -> read_body_length(req, length + byte_size(data))
    end
  end
end
