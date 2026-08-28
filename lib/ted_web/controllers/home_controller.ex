defmodule TedWeb.HomeController do
  use TedWeb, :controller
  use OpenApiSpex.ControllerSpecs

  tags ["Documentation"]
  security []

  operation :show,
    operation_id: "home",
    summary: "Open the interactive operation reference",
    responses: [found: "Redirect to the interactive operation reference"]

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> redirect(to: "/docs")
  end
end
