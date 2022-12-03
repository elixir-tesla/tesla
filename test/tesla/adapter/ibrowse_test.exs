defmodule Tesla.Adapter.IbrowseTest do
  use ExUnit.Case

  use Tesla.AdapterCase, adapter: Tesla.Adapter.Ibrowse

  use Tesla.AdapterCase.Basic
  use Tesla.AdapterCase.Multipart
  use Tesla.AdapterCase.StreamRequestBody

  # SSL test disabled on purpose
  # ibrowser seems to have a problem with "localhost" host, as explined in
  # https://github.com/cmullaparthi/ibrowse/issues/162
  #
  # In case of the test below it results in
  #   {:tls_alert, {:handshake_failure, 'TLS client: In state wait_cert_cr at ssl_handshake.erl:1990 generated CLIENT ALERT: Fatal - Handshake Failure\n {bad_cert,hostname_check_failed}'}}
  # while the same configuration works well with other adapters.
  #
  # use Tesla.AdapterCase.SSL,
  #   ssl_options: [
  #     verify: :verify_peer,
  #     cacertfile: Path.join([to_string(:code.priv_dir(:httparrot)), "/ssl/server-ca.crt"])
  #   ]
end
