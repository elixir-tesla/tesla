clients = [:ibrowse, :hackney, :gun, :finch, :castore, :mint]
Enum.map(clients, &Application.ensure_all_started/1)

ExUnit.configure(trace: false)
ExUnit.start()
