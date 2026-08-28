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
    claim_attempt_ttl = AgentAuth.claim_attempt_ttl()

    document = """
    # auth.md

    Ted supports agent registration for its headless strength and nutrition coaching service. The resource server and authorization server are both `#{origin}`. This document implements the [auth.md protocol](https://workos.com/auth-md/docs/auth-md). The structured protected resource metadata is authoritative if it differs from this document.

    ## 1. Discover

    A protected request without a valid credential returns:

    ```http
    HTTP/1.1 401 Unauthorized
    WWW-Authenticate: Bearer resource_metadata="#{origin}/.well-known/oauth-protected-resource"
    ```

    Fetch `#{origin}/.well-known/oauth-protected-resource` for the [Representational State Transfer interface](https://developer.mozilla.org/en-US/docs/Glossary/REST), or `#{origin}/.well-known/oauth-protected-resource/mcp` for the [Model Context Protocol](https://modelcontextprotocol.io/) server. Read `resource`, `resource_name`, `authorization_servers`, `scopes_supported`, and `bearer_methods_supported`.

    Fetch `#{origin}/.well-known/oauth-authorization-server`. Read `issuer`, `token_endpoint`, `revocation_endpoint`, `grant_types_supported`, and the complete `agent_auth` object. It describes `skill`, `identity_endpoint`, `claim_endpoint`, `events_endpoint`, `identity_types_supported`, `identity_assertion.assertion_types_supported`, and `events_supported`.

    ## Native Model Context Protocol clients

    Ted supports [OAuth 2.0 Dynamic Client Registration](https://www.rfc-editor.org/rfc/rfc7591) for native [Model Context Protocol](https://modelcontextprotocol.io/) clients. Read `registration_endpoint`, `authorization_endpoint`, `response_types_supported`, `code_challenge_methods_supported`, and `token_endpoint_auth_methods_supported` from the authorization-server metadata.

    Register a public client at `#{origin}/oauth2/register`, then start the authorization-code flow at `#{origin}/oauth2/authorize`. Ted requires the `S256` [Proof Key for Code Exchange](https://www.rfc-editor.org/rfc/rfc7636) method, an exact registered redirect address, and a token resource of `#{origin}/mcp`. The person signs in and explicitly approves the requested scopes before Ted redirects to the registered address. Exchange the resulting code at `#{origin}/oauth2/token`; a successful response includes a rotating refresh token.

    ## 2. Pick a method

    Ted supports `service_auth`. Use it when the person gives you their email and consents to connect. The person must sign in or create an account on a Ted-owned page before access is granted.

    `identity_assertion` and `anonymous` are not enabled. Their registration errors are `identity_assertion_not_enabled` and `anonymous_not_enabled`.

    ## 3. Register with service_auth

    ```http
    POST #{origin}/agent/identity
    Content-Type: application/json

    {"type":"service_auth","login_hint":"user@example.com"}
    ```

    A successful response has this shape and does not contain an access token or identity assertion:

    ```json
    {
      "registration_id": "reg_...",
      "registration_type": "service_auth",
      "claim_url": "#{origin}/agent/identity/claim",
      "claim_token": "clm_...",
      "claim_token_expires": "2026-08-26T12:00:00Z",
      "post_claim_scopes": #{scope_list},
      "claim": {
        "user_code": "123456",
        "expires_in": #{claim_attempt_ttl},
        "verification_uri": "#{origin}/agent/identity/claim?claim_attempt_token=cla_...",
        "interval": 5
      }
    }
    ```

    Keep `claim_token` private and in memory until the ceremony finishes. Show `claim.user_code` and `claim.verification_uri` to the person in one message. Tell them to open the link, sign in or create their account, verify the account email, and enter the code there. Never ask them to send the code back to you. Ted never emails this code.

    ## 4. Complete the claim ceremony

    The person opens `verification_uri`. Ted requires sign-in or sign-up for exactly the normalized `login_hint` email. For an unverified account, Ted emails a separate one-time verification link. The signed-in account and its verified email are checked when the claim page is rendered and again when the code is submitted.

    Poll no faster than `claim.interval`:

    ```http
    POST #{origin}/oauth2/token
    Content-Type: application/x-www-form-urlencoded

    grant_type=#{AgentAuth.claim_grant()}&claim_token=<claim_token>
    ```

    While confirmation is pending, Ted returns `authorization_pending`. Success returns a bearer access token and a service-signed identity assertion:

    ```json
    {
      "access_token": "tat_...",
      "token_type": "Bearer",
      "expires_in": 3600,
      "scope": "#{scopes}",
      "identity_assertion": "eyJ...",
      "assertion_expires": "<date-time>"
    }
    ```

    The access token in the claim response is bound to `#{origin}`. Do not use it for the Model Context Protocol. Exchange the identity assertion as shown below with `resource=#{origin}/mcp` first.

    ## 5. Exchange the identity assertion

    Ted uses the [JavaScript Object Notation Web Token bearer grant](https://www.rfc-editor.org/rfc/rfc7523). Exchange the same identity assertion for new access tokens until the assertion expires. Ted never issues a refresh token.

    ```http
    POST #{origin}/oauth2/token
    Content-Type: application/x-www-form-urlencoded

    grant_type=#{AgentAuth.jwt_bearer_grant()}&assertion=<identity_assertion>&resource=#{origin}/mcp
    ```

    Use `resource=#{origin}` for the Representational State Transfer interface and `resource=#{origin}/mcp` for the Model Context Protocol. A token is accepted only by the resource for which it was issued.

    ## 6. Use the access token

    Send `Authorization: Bearer <access_token>`. The [OpenAPI](https://www.openapis.org/) document is at `#{origin}/openapi.json`, interactive documentation is at `#{origin}/docs`, and the Model Context Protocol endpoint is at `#{origin}/mcp`.

    Use the operation catalog to record the person's profile, objectives, check-ins, meals, workouts, workout templates, and plans. Workout templates retain an ordered movement configuration, visual reference, and direct video link for every movement. Treat images and linked videos as learning aids, not as a substitute for qualified instruction when learning an unfamiliar movement. Coach only from recorded facts and explicit objectives. Do not diagnose illness, prescribe treatment, recommend extreme restriction, or present an estimate as a measurement. Meaningful pain stops progression and should prompt qualified professional care.

    ## 7. Errors

    | Endpoint | Error | Agent action |
    | --- | --- | --- |
    | `/agent/identity` | `invalid_request` or `invalid_login_hint` | Correct the request. |
    | `/agent/identity` | `anonymous_not_enabled` or `identity_assertion_not_enabled` | Use `service_auth`. |
    | `/agent/identity` | `rate_limited` | Wait before registering again. |
    | Claim page | `invalid_claim_token`, `account_mismatch`, or `expired_token` | Use the exact link and account, or restart registration. |
    | `/oauth2/token` | `authorization_pending` | Continue polling at the advertised interval. |
    | `/oauth2/token` | `slow_down` | Wait at least the advertised interval before polling again. |
    | `/oauth2/token` | `expired_token` or `invalid_grant` | Restart registration or correct the resource. |
    | `/oauth2/token` | `unsupported_grant_type` | Use an advertised grant type. |
    | Protected resource | `invalid_token` | Obtain a token for this resource. |
    | Protected resource | `insufficient_scope` or `forbidden` | Do not attempt an operation outside the authenticated account. |

    ## 8. Revoke credentials

    Credential revocation follows [Request for Comments 7009](https://www.rfc-editor.org/rfc/rfc7009) and is idempotent:

    ```http
    POST #{origin}/oauth2/revoke
    Content-Type: application/x-www-form-urlencoded

    token=<access_token>&token_type_hint=access_token
    ```

    The identity assertion remains exchangeable until it expires. Ted does not advertise provider security events because provider-verified registration is not enabled.

    ## Granted scopes

    - `profile:read` and `profile:write`: read or update the authenticated person's coaching profile.
    - `objectives:read` and `objectives:write`: read or change that person's objectives.
    - `check_ins:read` and `check_ins:write`: read or record body-weight and readiness check-ins.
    - `meals:read` and `meals:write`: read meal history, record meals, and request meal suggestions.
    - `workouts:read` and `workouts:write`: read or record strength sessions, and create, refine, or prepare named workout templates.
    - `plans:read` and `plans:write`: read, build, and review coaching plans.
    - `mcp`: connect to the Model Context Protocol server with a resource-bound token.

    A client that requests only `mcp` receives the complete coaching scope set above. Ted shows every granted scope on the consent page. A client can request `mcp` together with a narrower subset to limit its access.

    ## Service information

    - Service: `#{origin}`
    - Integration help: https://github.com/pepicrft/ted/issues
    """

    conn
    |> put_resp_content_type("text/markdown", "utf-8")
    |> send_resp(200, document)
  end
end
