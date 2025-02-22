defmodule Tesla.Mixfile do
  use Mix.Project

  @source_url "https://github.com/elixir-tesla/tesla"
  @version "1.14.1"

  def project do
    [
      app: :tesla,
      version: @version,
      description: description(),
      package: package(),
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      lockfile: lockfile(System.get_env("LOCKFILE")),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_core_path: "_build/#{Mix.env()}",
        plt_add_apps: [:mix, :inets, :idna, :ssl_verify_fun, :ex_unit],
        plt_add_deps: :apps_direct
      ],
      docs: docs(),
      preferred_cli_env: [coveralls: :test, "coveralls.html": :test]
    ]
  end

  def application do
    [extra_applications: [:logger, :ssl, :inets]]
  end

  defp description do
    "HTTP client library, with support for middleware and multiple adapters."
  end

  defp package do
    [
      maintainers: ["Tymon Tobolski"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      }
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp lockfile(nil), do: "mix.lock"
  defp lockfile(lockfile), do: "test/lockfiles/#{lockfile}.lock"

  defp deps do
    [
      {:mime, "~> 1.0 or ~> 2.0"},

      # http clients
      {:ibrowse, "4.4.2", optional: true},
      {:hackney, "~> 1.21", optional: true},
      {:gun, ">= 1.0.0", optional: true},
      {:finch, "~> 0.13", optional: true},
      {:castore, "~> 0.1 or ~> 1.0", optional: true},
      {:mint, "~> 1.0", optional: true},

      # json parsers
      {:jason, ">= 1.0.0", optional: true},
      {:poison, ">= 1.0.0", optional: true},
      {:exjsx, ">= 3.0.0", optional: true},

      # messagepack parsers
      {:msgpax, "~> 2.3", optional: true},

      # other
      {:fuse, "~> 2.4", optional: true},
      {:telemetry, "~> 0.4 or ~> 1.0", optional: true},
      {:mox, "~> 1.0", optional: true},

      # devtools
      {:opentelemetry_process_propagator, ">= 0.0.0", only: [:test, :dev]},
      {:excoveralls, ">= 0.0.0", only: :test, runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:mix_test_watch, ">= 0.0.0", only: :dev},
      {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:inch_ex, ">= 0.0.0", only: :docs},

      # httparrot dependencies
      {:httparrot, "~> 1.4", only: :test},
      {:cowlib, "~> 2.9", only: [:dev, :test], override: true},
      {:ranch, "~> 2.1", only: :test, override: true}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      skip_undefined_reference_warnings_on: [
        "CHANGELOG.md",
        "guides/howtos/migrations/v1-macro-migration.md"
      ],
      extra_section: "GUIDES",
      logo: "guides/elixir-tesla-logo.png",
      extras:
        [
          "README.md",
          LICENSE: [title: "License"]
          # TODO: add CHANGELOG.md
          # "CHANGELOG.md": [title: "Changelog"]
        ] ++ Path.wildcard("guides/**/*.{cheatmd,md}"),
      groups_for_extras: [
        Explanations: ~r"/explanations/",
        Cheatsheets: ~r"/cheatsheets/",
        "How-To's": ~r"/howtos/"
      ],
      groups_for_modules: [
        Behaviours: [
          Tesla.Adapter,
          Tesla.Middleware
        ],
        Adapters: [~r/Tesla.Adapter./],
        Middlewares: [~r/Tesla.Middleware./],
        TestSupport: [~r/Tesla.TestSupport./]
      ],
      nest_modules_by_prefix: [
        Tesla.Adapter,
        Tesla.Middleware
      ]
    ]
  end
end
