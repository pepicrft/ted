defmodule Ted.AgentAuthTest do
  use Ted.DataCase, async: true

  alias Ted.Accounts
  alias Ted.AgentAuth

  @issuer "https://ted.example.test"

  defmodule StaticKeys do
    @moduledoc false
    def fetch(_uri, opts), do: {:ok, Keyword.fetch!(opts, :jwks_document)}
  end

  test "anonymous access is limited until the person claims it", %{repo: repo} do
    opts = auth_opts(repo)
    assert {:ok, registration} = AgentAuth.create_anonymous_registration(opts)

    assert {:ok, pre_claim_token} =
             AgentAuth.exchange_assertion(
               registration.identity_assertion,
               @issuer <> "/mcp",
               opts
             )

    assert pre_claim_token.scope == "mcp"

    assert {:ok, authorization} =
             AgentAuth.authorize(
               pre_claim_token.access_token,
               ["mcp"],
               Keyword.put(opts, :resource, @issuer <> "/mcp")
             )

    assert is_nil(authorization.user_id)

    assert AgentAuth.authorize(
             pre_claim_token.access_token,
             ["profile:read"],
             Keyword.put(opts, :resource, @issuer <> "/mcp")
           ) == {:error, :insufficient_scope}

    assert {:ok, claim} =
             AgentAuth.start_anonymous_claim(
               registration.claim_token,
               "person@example.test",
               opts
             )

    assert {:ok, user} =
             Accounts.create_verified_agent_user(
               %{"email" => "person@example.test", "name" => "Person"},
               repo
             )

    assert {:ok, _claimed} =
             AgentAuth.confirm_claim(
               claim.claim_attempt_token,
               claim.user_code,
               user,
               opts
             )

    assert {:ok, claimed_token} = AgentAuth.exchange_claim(registration.claim_token, opts)
    assert "profile:read" in String.split(claimed_token.scope)

    assert AgentAuth.authorize(
             pre_claim_token.access_token,
             ["mcp"],
             Keyword.put(opts, :resource, @issuer <> "/mcp")
           ) == {:error, :invalid_token}
  end

  test "accepts a trusted provider assertion once and rejects replay", %{repo: repo} do
    now = 1_787_000_000
    private_key = JOSE.JWK.generate_key({:rsa, 2_048})
    {_, public_key} = private_key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    key_document = %{
      "keys" => [
        public_key
        |> Map.put("kid", "provider-key")
        |> Map.put("alg", "RS256")
        |> Map.put("use", "sig")
      ]
    }

    claims = %{
      "iss" => "https://agent-provider.example.test",
      "sub" => "provider-person-1",
      "aud" => @issuer,
      "iat" => now,
      "exp" => now + 600,
      "auth_time" => now - 60,
      "jti" => "provider-assertion-1",
      "client_id" => "trusted-client",
      "email" => "verified@example.test",
      "email_verified" => true,
      "name" => "Verified Person"
    }

    header = %{"alg" => "RS256", "kid" => "provider-key", "typ" => "oauth-id-jag+jwt"}
    {_, assertion} = private_key |> JOSE.JWT.sign(header, claims) |> JOSE.JWS.compact()

    opts =
      auth_opts(repo)
      |> Keyword.put(:now, now)
      |> Keyword.put(:jwks_client, StaticKeys)
      |> Keyword.put(:jwks_document, key_document)
      |> Keyword.put(:trusted_providers, [
        %{
          issuer: "https://agent-provider.example.test",
          jwks_uri: "https://agent-provider.example.test/.well-known/jwks.json",
          client_ids: ["trusted-client"]
        }
      ])

    assert {:ok, result} =
             AgentAuth.create_identity_registration(
               AgentAuth.identity_assertion_type(),
               assertion,
               opts
             )

    assert result.registration.registration_type == "identity_assertion"
    assert result.registration.claim_email == "verified@example.test"

    assert AgentAuth.create_identity_registration(
             AgentAuth.identity_assertion_type(),
             assertion,
             opts
           ) == {:error, :replay_detected}

    event_claims = %{
      "iss" => "https://agent-provider.example.test",
      "sub" => "provider-person-1",
      "aud" => @issuer,
      "iat" => now + 1,
      "jti" => "provider-revocation-1",
      "events" => %{AgentAuth.revocation_event() => %{}}
    }

    event_header = %{"alg" => "RS256", "kid" => "provider-key", "typ" => "secevent+jwt"}
    {_, event} = private_key |> JOSE.JWT.sign(event_header, event_claims) |> JOSE.JWS.compact()

    assert {:ok, 1} = AgentAuth.process_security_event(event, opts)

    assert AgentAuth.exchange_assertion(result.identity_assertion, @issuer, opts) ==
             {:error, :invalid_grant}
  end

  defp auth_opts(repo) do
    [
      index: repo,
      issuer: @issuer,
      user_code_hmac_key: "test-user-code-hmac-key",
      allow_ephemeral_signing_key: true
    ]
  end
end
