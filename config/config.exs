use Mix.Config

config :tesla, adapter: Tesla.Adapter.Httpc

if Mix.env() == :test do
  config :logger, :console,
    level: :debug,
    format: "$date $time [$level] $metadata$message\n"

  config :httparrot,
    http_port: 5080,
    https_port: 5443,
    ssl: true,
    unix_socket: false

  config :sasl,
    errlog_type: :error,
    sasl_error_logger: false

  config :tesla, MockClient, adapter: Tesla.Mock
end
