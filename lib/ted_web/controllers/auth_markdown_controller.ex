defmodule TedWeb.AuthMarkdownController do
  use TedWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ted.AgentAuth
  alias TedWeb.PublicOrigin

  tags ["Agent authentication"]
  security []

  operation :show,
    operation_id: "agent_auth_instructions",
    summary: "Read the auth.md agent registration instructions",
    responses: [ok: {"auth.md", "text/markdown", %Schema{type: :string}}]

  def show(conn, _params) do
    origin = PublicOrigin.from_conn(conn)
    scopes = Enum.join(AgentAuth.agent_scopes(), " ")
    scope_list = JSON.encode!(AgentAuth.agent_scopes())

    document = """
    # auth.md

    Ted is a headless strength and nutrition coach. The resource server and authorization server are both `#{origin}`. This document implements the [auth.md protocol](https://workos.com/auth-md/docs/auth-md). Structured discovery metadata is authoritative if it conflicts with this prose.

    ## 1. Discover

    A protected request without a valid credential returns:

    ```http
    HTTP/1.1 401 Unauthorized
    WWW-Authenticate: Bearer resource_metadata="#{origin}/.well-known/oauth-protected-resource"
    ```

    Fetch `#{origin}/.well-known/oauth-protected-resource`, or use `#{origin}/.well-known/oauth-protected-resource/mcp` when the target is the [Model Context Protocol](https://modelcontextprotocol.io/) endpoint. Read `resource`, `resource_name`, `authorization_servers`, `scopes_supported`, and `bearer_methods_supported`. Then fetch `#{origin}/.well-known/oauth-authorization-server` and read `issuer`, `token_endpoint`, `revocation_endpoint`, `grant_types_supported`, and the full `agent_auth` object: `skill`, `identity_endpoint`, `claim_endpoint`, `events_endpoint`, `identity_types_supported`, `identity_assertion.assertion_types_supported`, and `events_supported`.

    ## 2. Pick a method

    1. If the agent provider can mint an audience-bound Identity and Authorization Grant for `#{origin}`, use `identity_assertion`. Confirm its assertion type is advertised first.
    2. If the agent knows the person's email, use `service_auth`. The person must complete the claim ceremony before use.
    3. If neither is available, use `anonymous`. It can connect with the limited `#{Enum.join(AgentAuth.pre_claim_scopes(), " ")}` scope, but it cannot read or change coaching records before claim.

    ## 3. Register

    ### 3a. Provider-verified identity assertion

    ```http
    POST #{origin}/agent/identity
    Content-Type: application/json

    {"type":"identity_assertion","assertion_type":"#{AgentAuth.identity_assertion_type()}","assertion":"<provider_assertion>"}
    ```

    A clean match returns:

    ```json
    {"registration_id":"<id>","registration_type":"identity_assertion","identity_assertion":"<service_assertion>","assertion_expires":"<date-time>","scopes":#{scope_list}}
    ```

    An existing account without a prior provider link returns `401 interaction_required` plus claim materials. A stale provider authentication returns `401 login_required`.

    ### 3b. Email claim

    ```http
    POST #{origin}/agent/identity
    Content-Type: application/json

    {"type":"service_auth","login_hint":"user@example.com"}
    ```

    ```json
    {"registration_id":"<id>","registration_type":"service_auth","claim_url":"#{origin}/agent/identity/claim","claim_token":"<private_token>","claim_token_expires":"<date-time>","post_claim_scopes":#{scope_list},"claim":{"user_code":"123456","expires_in":600,"verification_uri":"#{origin}/agent/identity/claim?claim_attempt_token=<token>","interval":5}}
    ```

    ### 3c. Anonymous start

    ```http
    POST #{origin}/agent/identity
    Content-Type: application/json

    {"type":"anonymous"}
    ```

    ```json
    {"registration_id":"<id>","registration_type":"anonymous","identity_assertion":"<pre_claim_service_assertion>","assertion_expires":"<date-time>","pre_claim_scopes":["mcp"],"claim_url":"#{origin}/agent/identity/claim","claim_token":"<private_token>","claim_token_expires":"<date-time>","post_claim_scopes":#{scope_list}}
    ```

    ## 4. Claim ceremony

    Email registrations already contain a `claim` block. To claim an anonymous registration:

    ```http
    POST #{origin}/agent/identity/claim
    Content-Type: application/json

    {"claim_token":"<private_token>","email":"user@example.com"}
    ```

    Keep `claim_token` private. Show `verification_uri` and `user_code` together. Tell the person to open the link, authenticate on Ted, and type the code there. Never ask the person to send the code back to the agent.

    Poll no faster than the returned `interval`:

    ```http
    POST #{origin}/oauth2/token
    Content-Type: application/x-www-form-urlencoded

    grant_type=#{AgentAuth.claim_grant()}&claim_token=<private_token>
    ```

    `authorization_pending` means wait. `slow_down` means increase the polling interval. Success returns a standard token response plus `identity_assertion` and `assertion_expires`. For an anonymous registration, that new assertion replaces the pre-claim assertion and pre-claim access tokens are revoked.

    ## 5. Exchange the assertion

    Use the [JavaScript Object Notation Web Token bearer grant](https://www.rfc-editor.org/rfc/rfc7523) and optionally pin the token to the coaching or Model Context Protocol resource:

    ```http
    POST #{origin}/oauth2/token
    Content-Type: application/x-www-form-urlencoded

    grant_type=#{AgentAuth.jwt_bearer_grant()}&assertion=<identity_assertion>&resource=#{origin}/mcp
    ```

    ```json
    {"access_token":"<token>","token_type":"Bearer","expires_in":3600,"scope":"#{scopes}"}
    ```

    ## 6. Use and refresh

    Send `Authorization: Bearer <access_token>`. Use the operation catalog at `#{origin}/openapi.json` or the Model Context Protocol endpoint at `#{origin}/mcp`. When the access token expires, exchange the same identity assertion again. There is no refresh token. When the assertion expires or exchange returns `invalid_grant`, restart registration.

    Coach only from recorded facts and explicit objectives. Never diagnose illness, prescribe treatment, recommend extreme restriction, or present an estimate as a measurement. Pause progression and encourage qualified professional care for meaningful pain, disordered eating, pregnancy, or another concern outside ordinary coaching.

    ## 7. Errors

    | Endpoint | Error | Agent action |
    | --- | --- | --- |
    | `/agent/identity` | `invalid_issuer`, `invalid_signature`, `expired`, `replay_detected`, `invalid_audience`, `invalid_client_id`, `missing_verified_email`, `invalid_request` | Correct or renew the provider assertion. Stop on an untrusted issuer. |
    | `/agent/identity` | `anonymous_not_enabled`, `identity_assertion_not_enabled`, `service_auth_not_enabled` | Pick an advertised method. |
    | `/agent/identity` | `interaction_required` | Hand the returned claim ceremony to the person. |
    | `/agent/identity` | `login_required` | Ask the provider to reauthenticate the person and mint a fresh assertion. |
    | `/agent/identity/claim` | `invalid_claim_token`, `claimed_or_in_flight`, `claim_expired` | Correct the token, wait for the active attempt, or restart registration. |
    | `/oauth2/token` | `authorization_pending` | Wait at least the advertised interval. |
    | `/oauth2/token` | `slow_down` | Increase the polling interval. |
    | `/oauth2/token` | `expired_token` | Start a fresh anonymous claim attempt or registration. |
    | `/oauth2/token` | `invalid_grant`, `invalid_client`, `unsupported_grant_type` | Correct the request or restart registration. |

    ## 8. Revocation

    To revoke only one access token using [token revocation](https://www.rfc-editor.org/rfc/rfc7009):

    ```http
    POST #{origin}/oauth2/revoke
    Content-Type: application/x-www-form-urlencoded

    token=<access_token>&token_type_hint=access_token
    ```

    The service assertion survives and can be exchanged again. Trusted providers separately send a signed [Security Event Token](https://www.rfc-editor.org/rfc/rfc8417) to `#{origin}/agent/event/notify`. A valid `#{AgentAuth.revocation_event()}` event revokes the registration and every derived token. The agent then receives `invalid_grant` and must restart registration.

    Terms: `#{origin}/terms`. Privacy: `#{origin}/privacy`. Integration documentation: `#{origin}/docs`.
    """

    conn
    |> put_resp_content_type("text/markdown", "utf-8")
    |> send_resp(200, document)
  end
end
