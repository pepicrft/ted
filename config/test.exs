import Config

test_port = String.to_integer(System.get_env("TED_TEST_PORT", "4002"))

config :ted,
  agent_auth_sweeper: false,
  telegram: [bot_token: "test-token", webhook_secret: "test-secret"],
  rate_limits: [
    website: [scale_ms: 60_000, limit: 100_000],
    documentation: [scale_ms: 60_000, limit: 100_000],
    api: [scale_ms: 60_000, limit: 100_000],
    authentication: [scale_ms: 60_000, limit: 100_000],
    model_context_protocol: [scale_ms: 60_000, limit: 100_000]
  ]

config :ted, Ted.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database:
    System.get_env(
      "TED_TEST_DATABASE_NAME",
      "ted_test#{System.get_env("MIX_TEST_PARTITION")}"
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :ted, TedWeb.Endpoint,
  url: [host: "localhost", port: test_port, scheme: "http"],
  http: [ip: {127, 0, 0, 1}, port: test_port],
  server: false

config :ted, Ted.Mailer, adapter: Swoosh.Adapters.Test
config :argon2_elixir, t_cost: 1, m_cost: 8
config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
