defmodule Tesla.Mixfile do
  use Mix.Project

  def project do
    [
      app: :tesla,
      version: "0.5.2",
      description: description(),
      package: package(),
      source_url: "https://github.com/teamon/tesla",
      elixir: "~> 1.3",
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

  def applications(:test), do: applications(:dev) ++ [:httparrot]
  def applications(_), do: [:logger]

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

  defp deps do
    [
      # http clients
      {:ibrowse, "~> 4.2",   optional: true},
      {:hackney, "~> 1.6", optional: true},

      # json parsers
      {:exjsx,  ">= 0.1.0",  optional: true},
      {:poison, ">= 1.0.0",  optional: true},

      {:fuse, "~> 2.4", optional: true},

      # testing & docs
      {:httparrot,      "~> 0.4.1",  only: :test},
      {:excoveralls,    "~> 0.5",    only: :test},
      {:ex_doc,         "~> 0.13.0", only: :dev},
      {:mix_test_watch, "~> 0.2.6",  only: :dev},
      {:dialyxir,       "~> 0.3.5",  only: :dev}
    ]
  end
end
