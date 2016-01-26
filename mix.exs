defmodule Tesla.Mixfile do
  use Mix.Project

  def project do
    [app: :tesla,
     version: "0.2.1",
     description: description,
     package: package,
     source_url: "https://github.com/monterail/tesla",
     elixir: "~> 1.0",
     deps: deps,
     test_coverage: [tool: ExCoveralls]]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger]]
  end

  defp description do
    "HTTP client library, with support for middleware and multiple adapters."
  end

  defp package do
    [maintainers: ["Tymon Tobolski"],
     licenses: ["MIT"],
     links: %{"GitHub" => "https://github.com/monterail/tesla"}]
  end

  defp deps do
    [{:ibrowse, github: "cmullaparthi/ibrowse", tag: "v4.2", optional: true},
     {:exjsx, "~> 3.1.0", optional: true},
     {:excoveralls, "~> 0.3", only: :test},
     {:ex_doc, "~> 0.7", only: :dev}]
  end
end
