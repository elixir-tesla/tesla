defmodule Tesla.Mixfile do
  use Mix.Project

  def project do
    [
      app: :tesla,
      version: "0.10.0",
      description: description(),
      package: package(),
      source_url: "https://github.com/teamon/tesla",
      elixir: "~> 1.3",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      lockfile: lockfile(System.get_env("LOCKFILE")),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_add_apps: [:inets],
        plt_add_deps: :project
      ],
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: applications(Mix.env())]
  end

  def applications(:test), do: applications(:dev) ++ [:httparrot, :hackney, :ibrowse, :mox]
  def applications(_), do: [:logger, :ssl, :inets]

  defp description do
    "HTTP client library, with support for middleware and multiple adapters."
  end

  defp package do
    [
      maintainers: ["Tymon Tobolski"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/teamon/tesla"}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp lockfile(nil), do: "mix.lock"
  defp lockfile(lockfile), do: "test/lockfiles/#{lockfile}.lock"

  defp deps do
    [
      {:mime, "~> 1.0"},

      # http clients
      {:ibrowse, "~> 4.2", optional: true},
      {:hackney, "~> 1.6", optional: true},

      # json parsers
      {:exjsx, ">= 0.1.0", optional: true},
      {:poison, ">= 1.0.0", optional: true},
      {:fuse, "~> 2.4", optional: true},

      # testing & docs
      {:mox, "~> 0.3", only: :test},
      {:excoveralls, "~> 0.7.2", only: :test},
      {:httparrot, "~> 0.5.0", only: :test},
      {:ex_doc, "~> 0.16.1", only: :dev},
      {:mix_test_watch, "~> 0.4.1", only: :dev},
      {:dialyxir, "~> 0.5.1", only: :dev},
      {:inch_ex, only: :docs}
    ]
  end
end
