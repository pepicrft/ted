import Config

config :ted,
  ecto_repos: [Ted.Repo],
  agent_auth_sweeper: true,
  allowed_mcp_origins: ["http://localhost:4000", "http://127.0.0.1:4000"],
  rate_limits: [
    documentation: [scale_ms: 60_000, limit: 60],
    api: [scale_ms: 60_000, limit: 120],
    authentication: [scale_ms: 60_000, limit: 30],
    model_context_protocol: [scale_ms: 60_000, limit: 120]
  ],
  agent_auth: [
    registration_ttl_seconds: 86_400,
    claim_attempt_ttl_seconds: 600,
    registration_address_limit: 10,
    registration_global_limit: 100,
    claim_attempt_limit: 5,
    sign_in_attempt_limit: 10,
    assertion_ttl_seconds: 86_400,
    access_token_ttl_seconds: 3_600,
    poll_interval_seconds: 5,
    maximum_auth_age_seconds: 3_600,
    user_code_hmac_key: "development-user-code-hmac-key",
    trusted_providers: [],
    allow_ephemeral_signing_key: true
  ]

config :ted, TedWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  render_errors: [
    formats: [json: TedWeb.ErrorJSON],
    layout: false
  ],
  secret_key_base: "jIFizEmNBFSgwmjACbELNhTwODxuINgDTghhJjwgMhRgGGKjKkTiTHrIhadgRZBj",
  url: [host: "localhost"]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, JSON
config :postgrex, :json_library, JSON

# Telemetry is opt-in: an instance without a configured collector exports
# nothing and never opens a connection. `config/runtime.exs` turns the exporters
# on when OTEL_EXPORTER_OTLP_ENDPOINT is present.
config :ted, observability_enabled: false
config :opentelemetry, traces_exporter: :none

config :phoenix,
       :filter_parameters,
       ~w(password token email_verification_token claim_token claim_attempt_token user_code assertion)

config :ted, Ted.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, :api_client, Swoosh.ApiClient.Finch

import_config "#{config_env()}.exs"
