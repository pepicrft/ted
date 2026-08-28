defmodule TedWeb.OAuthController do
  use TedWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ted.AgentAuth
  alias Ted.Index
  alias Ted.OAuth
  alias TedWeb.PublicOrigin

  @claim_grant AgentAuth.claim_grant()
  @jwt_bearer_grant AgentAuth.jwt_bearer_grant()
  @authorization_code_grant "authorization_code"
  @refresh_token_grant "refresh_token"

  tags ["Agent authentication"]
  security []

  operation :token,
    operation_id: "exchange_agent_credential",
    summary: "Exchange an agent credential, authorization code, or refresh token",
    request_body:
      {"Token grant", "application/x-www-form-urlencoded",
       %Schema{type: :object, additionalProperties: true}},
    responses: [ok: {"Access token", "application/json", %Schema{type: :object}}]

  operation :revoke,
    operation_id: "revoke_agent_credential",
    summary: "Revoke one agent access token",
    request_body:
      {"Revocation request", "application/x-www-form-urlencoded",
       %Schema{
         type: :object,
         properties: %{
           token: %Schema{type: :string},
           token_type_hint: %Schema{type: :string}
         }
       }},
    responses: [ok: {"Credential revoked", "text/plain", %Schema{type: :string}}]

  def token(conn, %{"grant_type" => grant, "claim_token" => claim_token})
      when grant == @claim_grant do
    token_response(conn, AgentAuth.exchange_claim(claim_token, auth_opts(conn)))
  end

  def token(conn, %{"grant_type" => grant, "assertion" => assertion} = params)
      when grant == @jwt_bearer_grant do
    token_response(
      conn,
      AgentAuth.exchange_assertion(assertion, params["resource"], auth_opts(conn))
    )
  end

  def token(conn, %{"grant_type" => @authorization_code_grant} = params) do
    token_response(conn, OAuth.exchange_authorization_code(params, oauth_opts(conn)))
  end

  def token(conn, %{"grant_type" => @refresh_token_grant} = params) do
    token_response(conn, OAuth.refresh(params, oauth_opts(conn)))
  end

  def token(conn, %{"grant_type" => _grant}) do
    conn |> put_status(400) |> json(%{error: "unsupported_grant_type"})
  end

  def token(conn, _params), do: conn |> put_status(400) |> json(%{error: "invalid_request"})

  def revoke(conn, %{"token" => token}) do
    _result = OAuth.revoke(token, Map.get(conn.params, "client_id"), oauth_opts(conn))
    _result = AgentAuth.revoke_access_token(token, auth_opts(conn))
    send_resp(conn, 200, "")
  end

  def revoke(conn, _params), do: send_resp(conn, 200, "")

  defp token_response(conn, {:ok, response}) do
    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> json(response)
  end

  defp token_response(conn, {:error, reason}) do
    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> put_status(400)
    |> json(%{error: to_string(reason), error_description: error_description(reason)})
  end

  defp error_description(:authorization_pending), do: "The user has not confirmed access yet."
  defp error_description(:slow_down), do: "Polling is faster than the advertised interval."
  defp error_description(:expired_token), do: "The claim has expired."

  defp error_description(:invalid_grant),
    do: "The authorization code or refresh token is invalid."

  defp error_description(_reason), do: "The credential could not be exchanged."

  defp auth_opts(conn) do
    Keyword.merge(
      [
        index: conn.private[:ted_index] || Index.context(),
        issuer: PublicOrigin.from_conn(conn)
      ],
      conn.private[:ted_agent_auth_options] || []
    )
  end

  defp oauth_opts(conn) do
    [
      repo: conn.private[:ted_index] || Index.context(),
      issuer: PublicOrigin.from_conn(conn)
    ]
  end
end
