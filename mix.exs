defmodule Tesla.Mixfile do
  use Mix.Project

  @source_url "https://github.com/teamon/tesla"
  @version "1.4.1"

  def project do
    [
      app: :tesla,
      version: @version,
      description: description(),
      package: package(),
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      lockfile: lockfile(System.get_env("LOCKFILE")),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_add_apps: [:inets, :idna, :ssl_verify_fun],
        plt_add_deps: :project
      ],
      docs: docs()
    ]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
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
      {:finch, "~> 0.3", optional: true},
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
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: :dev},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:inch_ex, "~> 2.0", only: :docs}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "LICENSE"],
      groups_for_modules: [
        Behaviours: [
          Tesla.Adapter,
          Tesla.Middleware
        ],
        Adapters: [
          Tesla.Adapter.Finch,
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
          Tesla.Middleware.DecodeFormUrlencoded,
          Tesla.Middleware.DecodeJson,
          Tesla.Middleware.DecodeRels,
          Tesla.Middleware.DecompressResponse,
          Tesla.Middleware.DigestAuth,
          Tesla.Middleware.EncodeFormUrlencoded,
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
