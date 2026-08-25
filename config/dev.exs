import Config

config :ted, Ted.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: System.get_env("TED_DATABASE_NAME", "ted_dev"),
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :logger, level: :debug
