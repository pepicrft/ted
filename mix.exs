defmodule Ted.MixProject do
  use Mix.Project

  def project do
    [
      app: :ted,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [
        ignore_modules: [
          Inspect.Ted.Accounts.EmailVerificationToken,
          Inspect.Ted.Accounts.User,
          Ted.Application,
          Ted.Release,
          Ted.Repo,
          TedWeb,
          TedWeb.ApiSchemas.Error,
          TedWeb.Router.Helpers
        ]
      ],
      releases: [ted: []]
    ]
  end

  def application do
    [
      mod: {Ted.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp deps do
    [
      {:bandit, "~> 1.12"},
      {:argon2_elixir, "~> 4.0"},
      {:ecto_sql, "~> 3.14"},
      {:finch, "~> 0.23"},
      {:hammer, "~> 7.4"},
      {:jose, "~> 1.11"},
      {:open_api_spex, "~> 3.22"},
      {:opentelemetry, "~> 1.7"},
      {:opentelemetry_bandit, "~> 0.3.0"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:opentelemetry_exporter, "~> 1.10"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:otel_metric_exporter, "~> 0.4.4"},
      {:phoenix, "~> 1.8"},
      {:postgrex, "~> 0.22"},
      {:swoosh, "~> 1.26"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gen_smtp, "~> 1.3"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.7", only: :test},
      {:quokka, "~> 2.13", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      seed: ["run priv/repo/seeds.exs"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format --check-formatted --dot-formatter .formatter.standard.exs",
        "format --check-formatted",
        "credo --strict",
        "test"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_environment), do: ["lib"]
end
