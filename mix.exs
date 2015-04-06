defmodule Tesla.Mixfile do
  use Mix.Project

  def project do
    [app: :tesla,
     version: "0.1.0",
     description: description,
     package: package,
     elixir: "~> 1.0",
     deps: deps(Mix.env),
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
    [contributors: ["Tymon Tobolski"],
     licenses: ["MIT"],
     links: %{"GitHub" => "https://github.com/monterail/tesla"}]
  end

  defp deps(:dev) do
    [{:ibrowse, github: "cmullaparthi/ibrowse", tag: "v4.1.1"},
     {:exjsx, "~> 3.1.0"},
     {:excoveralls, "~> 0.3"}]
  end

  defp deps(:test) do
    deps(:dev)
  end

  defp deps(:prod) do
    []
  end
end
