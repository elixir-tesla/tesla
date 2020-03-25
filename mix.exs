defmodule Tesla.Mixfile do
  use Mix.Project

  @version "1.3.3"

  def project do
    [
      app: :tesla,
      version: @version,
      description: description(),
      package: package(),
      source_url: "https://github.com/teamon/tesla",
      elixir: "~> 1.5",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      lockfile: lockfile(System.get_env("LOCKFILE")),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_add_apps: [:inets],
        plt_add_deps: :project
      ],
      docs: docs()
    ]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: applications(Mix.env())]
  end

  def applications(:test), do: applications(:dev) ++ [:httparrot, :hackney, :ibrowse, :gun]
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
      {:ibrowse, "~> 4.4.0", optional: true},
      {:hackney, "~> 1.6", optional: true},
      {:gun, "~> 1.3", optional: true},
      {:castore, "~> 0.1", optional: true},
      {:mint, "~> 1.0", optional: true},

      # json parsers
      {:jason, ">= 1.0.0", optional: true},
      {:poison, ">= 1.0.0", optional: true},
      {:exjsx, ">= 3.0.0", optional: true},

      # other
      {:fuse, "~> 2.4", optional: true},
      {:telemetry, "~> 0.4", optional: true},

      # testing & docs
      {:excoveralls, "~> 0.8", only: :test},
      {:httparrot, "~> 1.2", only: :test},
      {:ex_doc, "~> 0.21", only: :dev},
      {:mix_test_watch, "~> 1.0", only: :dev},
      {:dialyxir, "~> 1.0.0-rc.3", only: [:dev, :test]},
      {:inch_ex, "~> 0.5.6", only: :docs}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md"],
      groups_for_modules: [
        Behaviours: [
          Tesla.Adapter,
          Tesla.Middleware
        ],
        Adapters: [
          Tesla.Adapter.Gun,
          Tesla.Adapter.Hackney,
          Tesla.Adapter.Httpc,
          Tesla.Adapter.Ibrowse,
          Tesla.Adapter.Mint
        ],
        Middlewares: [
          Tesla.Middleware.BaseUrl,
          Tesla.Middleware.BasicAuth,
          Tesla.Middleware.Compression,
          Tesla.Middleware.CompressRequest,
          Tesla.Middleware.DecodeJson,
          Tesla.Middleware.DecodeRels,
          Tesla.Middleware.DecompressResponse,
          Tesla.Middleware.DigestAuth,
          Tesla.Middleware.EncodeJson,
          Tesla.Middleware.FollowRedirects,
          Tesla.Middleware.FormUrlencoded,
          Tesla.Middleware.Fuse,
          Tesla.Middleware.Headers,
          Tesla.Middleware.JSON,
          Tesla.Middleware.KeepRequest,
          Tesla.Middleware.Logger,
          Tesla.Middleware.MethodOverride,
          Tesla.Middleware.Opts,
          Tesla.Middleware.PathParams,
          Tesla.Middleware.Query,
          Tesla.Middleware.Retry,
          Tesla.Middleware.Telemetry,
          Tesla.Middleware.Timeout
        ]
      ],
      nest_modules_by_prefix: [
        Tesla.Adapter,
        Tesla.Middleware
      ]
    ]
  end
end
