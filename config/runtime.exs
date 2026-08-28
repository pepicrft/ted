import Config

port_variable = if config_env() == :test, do: "TED_TEST_PORT", else: "TED_PORT"
default_port = if config_env() == :test, do: "4002", else: "4000"
port = System.get_env(port_variable, default_port) |> String.to_integer()
public_host = System.get_env("TED_HOST", "localhost")
public_scheme = System.get_env("TED_SCHEME", if(config_env() == :prod, do: "https", else: "http"))

public_port =
  System.get_env(
    "TED_URL_PORT",
    if(public_scheme == "https", do: "443", else: Integer.to_string(port))
  )
  |> String.to_integer()

default_public_origin =
  if (public_scheme == "https" and public_port == 443) or
       (public_scheme == "http" and public_port == 80) do
    "#{public_scheme}://#{public_host}"
  else
    "#{public_scheme}://#{public_host}:#{public_port}"
  end

allowed_mcp_origins =
  System.get_env("TED_ALLOWED_MCP_ORIGINS", default_public_origin)
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))

analytics_host = System.get_env("SMOLANALYTICS_HOST")
analytics_write_key = System.get_env("SMOLANALYTICS_WRITE_KEY")

analytics_enabled =
  Enum.all?([analytics_host, analytics_write_key], fn value ->
    is_binary(value) and String.trim(value) != ""
  end)

if analytics_enabled and config_env() == :prod and URI.parse(analytics_host).scheme != "https" do
  raise "SMOLANALYTICS_HOST must use HTTPS in production"
end

case System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
  endpoint when is_binary(endpoint) and endpoint != "" ->
    config :ted, observability_enabled: true
    config :opentelemetry, traces_exporter: :otlp
    config :opentelemetry_exporter, otlp_endpoint: endpoint
    config :otel_metric_exporter, otlp_endpoint: endpoint

  _endpoint ->
    config :ted, observability_enabled: false
    config :opentelemetry, traces_exporter: :none
end

agent_auth_private_key = System.get_env("TED_AGENT_AUTH_PRIVATE_KEY_PEM")

trusted_agent_providers =
  case System.get_env("TED_AGENT_AUTH_TRUSTED_PROVIDERS_JSON") do
    nil ->
      []

    encoded ->
      case JSON.decode(encoded) do
        {:ok, providers} when is_list(providers) -> providers
        _invalid -> raise "TED_AGENT_AUTH_TRUSTED_PROVIDERS_JSON must be a JSON array"
      end
  end

rate_limit_window = System.get_env("TED_RATE_LIMIT_WINDOW_MS", "60000") |> String.to_integer()

if config_env() == :prod do
  database_url = System.fetch_env!("TED_DATABASE_URL")
  secret_key_base = System.fetch_env!("TED_SECRET_KEY_BASE")

  database_transport_security =
    case System.get_env("TED_DATABASE_SSL", "true") do
      value when value in ~w(false 0) ->
        false

      _value ->
        certificate_authority_file =
          System.fetch_env!("TED_DATABASE_CERTIFICATE_AUTHORITY_FILE")

        database_host = database_url |> URI.parse() |> Map.fetch!(:host)

        [
          verify: :verify_peer,
          cacertfile: certificate_authority_file,
          server_name_indication: String.to_charlist(database_host),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
    end

  socket_options = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :ted, Ted.Repo,
    url: database_url,
    ssl: database_transport_security,
    pool_size: System.get_env("TED_POOL_SIZE", "10") |> String.to_integer(),
    socket_options: socket_options

  config :ted, TedWeb.Endpoint, secret_key_base: secret_key_base
  config :ted, :agent_auth, user_code_hmac_key: secret_key_base

  config :ted, Ted.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: System.get_env("TED_SMTP_RELAY", "localhost"),
    port: System.get_env("TED_SMTP_PORT", "587") |> String.to_integer(),
    auth: :never,
    tls: :never,
    retries: 2,
    no_mx_lookups: true
end

config :ted,
  allowed_mcp_origins: allowed_mcp_origins,
  email_from:
    {System.get_env("TED_EMAIL_FROM_NAME", "Ted"),
     System.get_env("TED_EMAIL_FROM_ADDRESS", "ted@example.com")},
  telegram: [
    bot_token: System.get_env("TED_TELEGRAM_BOT_TOKEN"),
    webhook_secret: System.get_env("TED_TELEGRAM_WEBHOOK_SECRET")
  ],
  rate_limits: [
    documentation: [
      scale_ms: rate_limit_window,
      limit: System.get_env("TED_RATE_LIMIT_DOCUMENTATION", "60") |> String.to_integer()
    ],
    api: [
      scale_ms: rate_limit_window,
      limit: System.get_env("TED_RATE_LIMIT_API", "120") |> String.to_integer()
    ],
    authentication: [
      scale_ms: rate_limit_window,
      limit: System.get_env("TED_RATE_LIMIT_AUTHENTICATION", "30") |> String.to_integer()
    ],
    model_context_protocol: [
      scale_ms: rate_limit_window,
      limit: System.get_env("TED_RATE_LIMIT_MCP", "120") |> String.to_integer()
    ]
  ],
  agent_auth: [
    registration_ttl_seconds: 86_400,
    claim_attempt_ttl_seconds:
      System.get_env("TED_AGENT_AUTH_CLAIM_ATTEMPT_TTL_SECONDS", "600")
      |> String.to_integer(),
    registration_address_limit:
      System.get_env("TED_AGENT_AUTH_ADDRESS_LIMIT", "10") |> String.to_integer(),
    registration_global_limit:
      System.get_env("TED_AGENT_AUTH_GLOBAL_LIMIT", "100") |> String.to_integer(),
    claim_attempt_limit:
      System.get_env("TED_AGENT_AUTH_CLAIM_ATTEMPT_LIMIT", "5") |> String.to_integer(),
    sign_in_attempt_limit:
      System.get_env("TED_AGENT_AUTH_SIGN_IN_ATTEMPT_LIMIT", "10") |> String.to_integer(),
    assertion_ttl_seconds:
      System.get_env("TED_AGENT_AUTH_ASSERTION_TTL_SECONDS", "86400") |> String.to_integer(),
    access_token_ttl_seconds:
      System.get_env("TED_AGENT_AUTH_ACCESS_TOKEN_TTL_SECONDS", "3600") |> String.to_integer(),
    poll_interval_seconds: 5,
    maximum_auth_age_seconds:
      System.get_env("TED_AGENT_AUTH_MAXIMUM_AUTH_AGE_SECONDS", "3600")
      |> String.to_integer(),
    trusted_providers: trusted_agent_providers,
    private_key_pem: agent_auth_private_key,
    allow_ephemeral_signing_key:
      System.get_env(
        "TED_AGENT_AUTH_ALLOW_EPHEMERAL_KEY",
        if(config_env() == :prod, do: "false", else: "true")
      ) in ~w(true 1)
  ]

if System.get_env("TED_SERVER") in ~w(true 1) or System.get_env("PHX_SERVER") in ~w(true 1) do
  config :ted, TedWeb.Endpoint, server: true
end

config :ted, TedWeb.Endpoint,
  http: [
    ip: if(config_env() == :prod, do: {0, 0, 0, 0}, else: {127, 0, 0, 1}),
    port: port
  ],
  url: [scheme: public_scheme, host: public_host, port: public_port],
  analytics: [
    enabled: analytics_enabled,
    host: analytics_host,
    write_key: analytics_write_key
  ]
