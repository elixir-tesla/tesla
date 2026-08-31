defmodule Tesla.TestSupport.TcpProxy do
  @moduledoc false

  def start(opts) do
    report_to = Keyword.fetch!(opts, :report_to)
    on_connect = Keyword.fetch!(opts, :on_connect)

    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen)
    pid = spawn(fn -> serve(listen, report_to, on_connect) end)

    {:ok, pid, port}
  end

  defp serve(listen, report_to, on_connect) do
    {:ok, socket} = :gen_tcp.accept(listen)
    :gen_tcp.close(listen)

    send(report_to, {:tcp_proxy_request, read_request(socket, "")})

    case on_connect do
      {:reject, status, reason} ->
        body = "denied"

        :gen_tcp.send(socket, [
          "HTTP/1.1 #{status} #{reason}\r\n",
          "content-length: #{byte_size(body)}\r\n",
          "\r\n",
          body
        ])

        :gen_tcp.close(socket)

      {:tunnel, host, port} ->
        {:ok, upstream} = :gen_tcp.connect(host, port, [:binary, active: true])
        :gen_tcp.send(socket, "HTTP/1.1 200 Connection established\r\n\r\n")
        :ok = :inet.setopts(socket, active: true)
        relay(socket, upstream)
    end
  end

  defp read_request(socket, acc) do
    if String.contains?(acc, "\r\n\r\n") do
      acc
    else
      {:ok, data} = :gen_tcp.recv(socket, 0)
      read_request(socket, acc <> data)
    end
  end

  defp relay(client, upstream) do
    receive do
      {:tcp, ^client, data} ->
        :gen_tcp.send(upstream, data)
        relay(client, upstream)

      {:tcp, ^upstream, data} ->
        :gen_tcp.send(client, data)
        relay(client, upstream)

      {:tcp_closed, _socket} ->
        :ok

      {:tcp_error, _socket, _reason} ->
        :ok
    end
  end
end
