defmodule Tesla.TestSupport.TLS do
  @moduledoc """
  TLS material for the local HTTPS test servers, generated once per test run.

  The certificate bundled with httparrot expires, so tests use a freshly issued
  chain instead of files that can go stale.
  """

  @key {__MODULE__, :files}

  def generate! do
    %{server_config: server_config, client_config: client_config} =
      :public_key.pkix_test_data(%{
        server_chain: %{
          root: cert_opts(),
          peer: [extensions: [localhost_subject_alt_name()]] ++ cert_opts()
        },
        client_chain: %{root: cert_opts(), peer: cert_opts()}
      })

    dir = Path.join(System.tmp_dir!(), "tesla-test-tls-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    {key_type, key_der} = Keyword.fetch!(server_config, :key)

    files = %{
      cacertfile:
        write_pem!(dir, "ca.crt", Enum.map(client_config[:cacerts], &{:Certificate, &1})),
      certfile:
        write_pem!(dir, "server.crt", [{:Certificate, Keyword.fetch!(server_config, :cert)}]),
      keyfile: write_pem!(dir, "server.key", [{key_type, key_der}])
    }

    :persistent_term.put(@key, files)
    files
  end

  def cacertfile, do: fetch!(:cacertfile)
  def certfile, do: fetch!(:certfile)
  def keyfile, do: fetch!(:keyfile)

  defp fetch!(name), do: Map.fetch!(:persistent_term.get(@key), name)

  defp write_pem!(dir, name, entries) do
    path = Path.join(dir, name)

    pem =
      :public_key.pem_encode(Enum.map(entries, fn {type, der} -> {type, der, :not_encrypted} end))

    File.write!(path, pem)
    path
  end

  defp cert_opts, do: [key: {:namedCurve, :secp256r1}, digest: :sha256]

  defp localhost_subject_alt_name do
    {:Extension, {2, 5, 29, 17}, false, [dNSName: ~c"localhost", iPAddress: <<127, 0, 0, 1>>]}
  end
end
