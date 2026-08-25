defmodule Ted.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    setup_observability()

    children =
      [TedWeb.Telemetry, Ted.Repo] ++
        agent_auth_sweeper_child() ++
        [Ted.RateLimit, {Finch, name: Ted.Finch}, TedWeb.Endpoint]

    Supervisor.start_link(children, strategy: :one_for_one, name: Ted.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    TedWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Traces, structured logs, and the Ecto and web instrumentation are only
  # attached when a collector is configured, so an instance without one does not
  # pay for spans nobody exports. See `config/runtime.exs`.
  defp setup_observability do
    if Application.get_env(:ted, :observability_enabled, false) do
      :ok = Logger.add_handlers(:ted)
      :ok = OpentelemetryBandit.setup(public_endpoint: true)
      :ok = OpentelemetryPhoenix.setup(adapter: :bandit)
      :ok = OpentelemetryEcto.setup([:ted, :repo])
    end

    :ok
  end

  defp agent_auth_sweeper_child do
    if Application.get_env(:ted, :agent_auth_sweeper, true),
      do: [Ted.AgentAuth.ExpirationSweeper],
      else: []
  end
end
