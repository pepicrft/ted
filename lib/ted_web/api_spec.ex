defmodule TedWeb.ApiSpec do
  @moduledoc "The OpenAPI document for every supported Ted operation."

  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server}
  alias TedWeb.Router

  @impl true
  def spec do
    %OpenApi{
      info: %Info{
        title: "Ted coaching interface",
        version: "0.1.0",
        description:
          "Record strength training, nutrition, and daily readiness through a headless coaching service."
      },
      servers: [%Server{url: TedWeb.PublicOrigin.default()}],
      components: %Components{
        securitySchemes: %{
          "bearerAuth" => %SecurityScheme{type: "http", scheme: "bearer"}
        }
      },
      security: [%{"bearerAuth" => []}],
      paths: Paths.from_router(Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
