defmodule TedWeb.OAuthRegistrationController do
  use TedWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ted.OAuth
  alias TedWeb.PublicOrigin

  tags ["OAuth"]
  security []

  operation :register,
    operation_id: "register_oauth_client",
    summary: "Dynamically register a public OAuth client",
    request_body:
      {"Client metadata", "application/json",
       %Schema{
         type: :object,
         properties: %{
           client_name: %Schema{type: :string},
           redirect_uris: %Schema{type: :array, items: %Schema{type: :string}},
           grant_types: %Schema{type: :array, items: %Schema{type: :string}},
           response_types: %Schema{type: :array, items: %Schema{type: :string}},
           token_endpoint_auth_method: %Schema{type: :string}
         },
         required: [:redirect_uris]
       }},
    responses: [
      created: {"Registered client", "application/json", %Schema{type: :object}},
      bad_request: {"Invalid client metadata", "application/json", %Schema{type: :object}}
    ]

  def register(conn, params) do
    case OAuth.register_client(params, oauth_opts(conn)) do
      {:ok, client} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_status(:created)
        |> json(client)

      {:error, reason} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_status(:bad_request)
        |> json(%{
          error: error_code(reason),
          error_description: error_description(reason)
        })
    end
  end

  defp error_description(:invalid_redirect_uri),
    do: "Register an HTTPS redirect address or an HTTP loopback redirect address."

  defp error_description(_reason), do: "The client metadata is not supported."

  defp error_code(:invalid_redirect_uri), do: "invalid_redirect_uri"
  defp error_code(_reason), do: "invalid_client_metadata"

  defp oauth_opts(conn) do
    [
      repo: conn.private[:ted_index] || Ted.Index.context(),
      issuer: PublicOrigin.from_conn(conn)
    ]
  end
end
