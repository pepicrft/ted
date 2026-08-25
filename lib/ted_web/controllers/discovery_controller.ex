defmodule TedWeb.DiscoveryController do
  use TedWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ted.AgentAuth
  alias TedWeb.PublicOrigin

  tags ["Agent authentication"]
  security []

  operation :protected_resource,
    operation_id: "get_oauth_protected_resource",
    summary: "Discover authorization for the coaching interface",
    responses: [ok: {"Protected resource metadata", "application/json", %Schema{type: :object}}]

  operation :mcp_protected_resource,
    operation_id: "get_mcp_protected_resource",
    summary: "Discover authorization for the Model Context Protocol server",
    responses: [ok: {"Protected resource metadata", "application/json", %Schema{type: :object}}]

  operation :authorization_server,
    operation_id: "get_oauth_authorization_server",
    summary: "Discover auth.md registration and token endpoints",
    responses: [ok: {"Authorization server metadata", "application/json", %Schema{type: :object}}]

  operation :jwks,
    operation_id: "get_agent_auth_signing_keys",
    summary: "Read public keys for service identity assertions",
    responses: [ok: {"Public signing keys", "application/json", %Schema{type: :object}}]

  operation :mcp_server_card,
    operation_id: "get_mcp_server_card",
    summary: "Discover the Ted Model Context Protocol server",
    responses: [ok: {"Server card", "application/json", %Schema{type: :object}}]

  operation :event_notify,
    operation_id: "receive_agent_security_event",
    summary: "Receive a provider security event when that optional flow is enabled",
    request_body: {"Security event", "application/secevent+jwt", %Schema{type: :string}},
    responses: [
      bad_request: {"Events are not enabled", "application/json", %Schema{type: :object}}
    ]

  def protected_resource(conn, _params),
    do: json(conn, protected_resource_document(PublicOrigin.from_conn(conn)))

  def mcp_protected_resource(conn, _params) do
    origin = PublicOrigin.from_conn(conn)

    json(conn, %{
      resource: origin <> "/mcp",
      resource_name: "Ted Model Context Protocol server",
      authorization_servers: [origin],
      scopes_supported: AgentAuth.scopes(),
      bearer_methods_supported: ["header"],
      resource_documentation: origin <> "/auth.md"
    })
  end

  def authorization_server(conn, _params) do
    origin = PublicOrigin.from_conn(conn)

    json(conn, %{
      resource: origin,
      authorization_servers: [origin],
      scopes_supported: AgentAuth.scopes(),
      bearer_methods_supported: ["header"],
      issuer: origin,
      token_endpoint: origin <> "/oauth2/token",
      revocation_endpoint: origin <> "/oauth2/revoke",
      grant_types_supported: [AgentAuth.claim_grant(), AgentAuth.jwt_bearer_grant()],
      token_endpoint_auth_methods_supported: ["none"],
      jwks_uri: origin <> "/.well-known/jwks.json",
      agent_auth: %{
        skill: origin <> "/auth.md",
        identity_endpoint: origin <> "/agent/identity",
        claim_endpoint: origin <> "/agent/identity/claim",
        events_endpoint: origin <> "/agent/event/notify",
        identity_types_supported: ["anonymous", "identity_assertion", "service_auth"],
        anonymous: %{pre_claim_scopes: AgentAuth.pre_claim_scopes()},
        identity_assertion: %{
          assertion_types_supported: [AgentAuth.identity_assertion_type()]
        },
        events_supported: [AgentAuth.revocation_event()]
      }
    })
  end

  def jwks(conn, _params) do
    case AgentAuth.jwks() do
      {:ok, keys} ->
        json(conn, keys)

      {:error, _reason} ->
        conn |> put_status(503) |> json(%{error: "signing_key_unavailable"})
    end
  end

  def mcp_server_card(conn, _params) do
    origin = PublicOrigin.from_conn(conn)

    json(conn, %{
      name: "Ted",
      description: "Record coaching inputs and build strength and nutrition plans.",
      version: "0.1.0",
      transport: %{
        type: "streamable-http",
        url: origin <> "/mcp",
        protocol_versions: ["2025-06-18", "2025-03-26"]
      },
      authentication: %{
        type: "oauth2",
        protected_resource_metadata: origin <> "/.well-known/oauth-protected-resource/mcp",
        agent_registration: origin <> "/auth.md"
      }
    })
  end

  def event_notify(conn, _params) do
    with {:ok, token, conn} <- security_event_token(conn),
         {:ok, _count} <-
           AgentAuth.process_security_event(token,
             index: conn.private[:ted_index] || Ted.Index.context(),
             issuer: PublicOrigin.from_conn(conn)
           ) do
      send_resp(conn, 202, "")
    else
      {:error, reason, conn} ->
        conn
        |> put_status(400)
        |> json(%{err: to_string(reason), description: "The security event was rejected."})

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{err: to_string(reason), description: "The security event was rejected."})
    end
  end

  defp security_event_token(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, conn} when byte_size(body) > 0 -> {:ok, String.trim(body), conn}
      {:ok, _body, conn} -> {:error, :invalid_request, conn}
      {:more, _body, conn} -> {:error, :invalid_request, conn}
      {:error, reason} -> {:error, reason, conn}
    end
  end

  defp protected_resource_document(origin) do
    %{
      resource: origin,
      resource_name: "Ted coaching interface",
      authorization_servers: [origin],
      scopes_supported: AgentAuth.scopes(),
      bearer_methods_supported: ["header"],
      resource_documentation: origin <> "/auth.md"
    }
  end
end
