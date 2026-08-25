defmodule TedWeb.OpenApiController do
  use TedWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{OpenApi, Schema}
  alias TedWeb.ApiSpec

  tags ["Documentation"]
  security []

  operation :show,
    operation_id: "get_openapi_document",
    summary: "Read the machine-readable application programming interface description",
    responses: [ok: {"OpenAPI document", "application/json", %Schema{type: :object}}]

  def show(conn, _params) do
    document = ApiSpec.spec() |> OpenApi.to_map() |> JSON.encode!()

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(200, document)
  end
end
