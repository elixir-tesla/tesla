clients = [:ibrowse, :hackney, :gun, :finch, :castore, :mint]
Enum.map(clients, &Application.ensure_all_started/1)

Mox.defmock(Tesla.TestSupport.MockAdapter, for: Tesla.Adapter)

ExUnit.start()
