clients = [:ibrowse, :hackney, :gun, :finch, :castore, :mint]
Enum.map(clients, &Application.ensure_all_started/1)

tls = Tesla.TestSupport.TLS.generate!()
:ok = :cowboy.stop_listener(:https)

{:ok, _} =
  :cowboy.start_tls(
    :https,
    [
      port: Application.fetch_env!(:httparrot, :https_port),
      certfile: tls.certfile,
      keyfile: tls.keyfile
    ],
    :ranch.get_protocol_options(:http)
  )

Mox.defmock(Tesla.TestSupport.MockAdapter, for: Tesla.Adapter)

ExUnit.start()
