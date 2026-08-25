import Config

config :ted, TedWeb.Endpoint, server: false
config :ted, secure_cookies: true
config :logger, level: :info

# Application logs, including crashes and error reports, are bridged onto the
# same OpenTelemetry pipeline that carries traces and metrics. The handler is
# attached at boot by `Ted.Application` and only when a collector endpoint
# is configured.
config :ted, :logger, [
  {:handler, :ted_opentelemetry, OtelMetricExporter.LogHandler,
   %{
     config: %{
       metadata: [:application, :domain, :line, :mfa, :pid],
       metadata_map: %{request_id: "http.request.id"}
     }
   }}
]

config :opentelemetry, span_processor: :batch

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_compression: :gzip

config :otel_metric_exporter,
  otlp_protocol: :http_protobuf,
  otlp_compression: :gzip
