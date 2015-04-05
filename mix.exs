defmodule Tesla.Mixfile do
  use Mix.Project

  def project do
    [app: :tesla,
     version: "0.0.1",
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

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
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
