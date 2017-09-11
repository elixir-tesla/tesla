defmodule Tesla.Mixfile do
  use Mix.Project

  def project do
    [
      app: :tesla,
      version: "0.7.2",
      description: description(),
      package: package(),
      source_url: "https://github.com/teamon/tesla",
      elixir: "~> 1.3",
      elixirc_paths: elixirc_paths(Mix.env),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_add_apps: [:inets],
        plt_add_deps: :project
      ],
      docs: [extras: ["README.md"]]
    ]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: applications(Mix.env)]
  end

  def applications(:test), do: applications(:dev) ++ [:httparrot, :hackney, :ibrowse]
  def applications(_), do: [:logger, :ssl]

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
  defp elixirc_paths(_),     do: ["lib"]

  defp deps do
    [
      {:mime, "~> 1.0"},

      # http clients
      {:ibrowse, "~> 4.2",   optional: true},
      {:hackney, "~> 1.6", optional: true},

      # json parsers
      {:exjsx,  ">= 0.1.0",  optional: true},
      {:poison, ">= 1.0.0",  optional: true},

      {:fuse, "~> 2.4", optional: true},

      # testing & docs
      {:excoveralls,    "~> 0.7.2",    only: :test},
      {:httparrot,      "~> 0.5.0",  only: :test},
      {:ex_doc,         "~> 0.16.1", only: :dev},
      {:mix_test_watch, "~> 0.4.1",  only: :dev},
      {:dialyxir,       "~> 0.5.1",  only: :dev}
    ]
  end
end
