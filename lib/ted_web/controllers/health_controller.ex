defmodule TedWeb.HealthController do
  use TedWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Ted.Index
  alias Ted.Operations
  alias TedWeb.ApiSchemas.Status

  tags ["Service"]
  security []

  operation :show,
    operation_id: "health",
    summary: "Check service health",
    responses: [ok: {"Service is ready", "application/json", Status}]

  def show(conn, _params) do
    repo = conn.private[:ted_index] || Index.context()
    TedWeb.ApiResponse.send_result(conn, Operations.call("health", %{}, repo))
  end
end
