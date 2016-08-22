# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :tesla, adapter: :httpc,
               json: :exjsx

if Mix.env == :test do
  config :httparrot, http_port: 8888
end
