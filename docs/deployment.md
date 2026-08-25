# Deploying Ted to Indie

Ted is reconciled from the `main` branch of `pepicrft/ted`. The Indie repository owns the source, image automation, runner, and production release declarations. The Ted repository owns the application, container, chart, and production values.

## Required secret record

Create an Infisical item named `ted` with these fields before enabling reconciliation:

| Field | Purpose |
| --- | --- |
| `POSTGRES_PASSWORD` | Password for the application database user. |
| `SECRET_KEY_BASE` | Phoenix cookie and message-signing secret. Generate it with `mise exec -- mix phx.gen.secret`. |
| `API_KEY` | Initial operator credential for administrative use. Use a long random value. |
| `AGENT_AUTH_PRIVATE_KEY_PEM` | Stable private signing key in Privacy-Enhanced Mail format for service identity assertions. |
| `TELEGRAM_BOT_TOKEN` | Token issued by Telegram's BotFather. |
| `TELEGRAM_WEBHOOK_SECRET` | Long random value checked on every Telegram webhook request. |
| `LEGAL_OPERATOR_NAME` | Name shown in the legal pages. |
| `LEGAL_OPERATOR_ADDRESS` | Postal address shown in the legal pages. |
| `LEGAL_CONTACT_EMAIL` | Contact address shown in the legal pages. |

Generate the service signing key with OpenSSL:

```sh
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072
```

Here, RSA means the [Rivest-Shamir-Adleman public-key system](https://www.rfc-editor.org/rfc/rfc8017). Keep the complete output, including its header and footer, in `AGENT_AUTH_PRIVATE_KEY_PEM`.

The existing `kubernetes` secret item supplies the GitHub Container Registry pull username and token. The cluster object-storage controller creates the database backup credential after the bucket claim is reconciled.

## Trusted agent providers

Email claims and anonymous starts work without a provider trust list. Provider-verified identity assertions require `TED_AGENT_AUTH_TRUSTED_PROVIDERS_JSON`. The value is a JavaScript Object Notation array:

```json
[
  {
    "issuer": "https://agent-provider.example.com",
    "jwks_uri": "https://agent-provider.example.com/.well-known/jwks.json",
    "client_ids": ["ted-production"]
  }
]
```

Add the value to `extraEnv` in `deploy/values-production.yaml` after choosing the providers that may attest identities. Ted rejects every provider assertion while this list is empty. Each configured provider must issue audience-bound assertions for `https://ted.pepicrft.me` and send signed revocation events to `https://ted.pepicrft.me/agent/event/notify`.

The `jwks_uri` field points to the provider's [JSON Web Key Set](https://www.rfc-editor.org/rfc/rfc7517). Ted uses it only after the assertion issuer matches an explicit trust-list entry.

## Publication order

1. Create the secret fields above.
2. Publish the Ted repository and merge the application to `main`.
3. Reconcile the Indie management declarations so the dedicated runner and Ted source exist.
4. Let the Ted workflow publish the first `main` container image.
5. Merge the Indie release declaration. Image automation records the immutable image digest after the first image scan.
6. Wait for the release, PostgreSQL cluster, external secrets, certificate, ingress, and backup to become ready.

The initial digest in the Indie release is intentionally empty. A deployment cannot become ready until the first container image exists and image automation writes its digest.

## Readiness checks

After reconciliation, verify:

```sh
curl --fail https://ted.pepicrft.me/health
curl --fail https://ted.pepicrft.me/.well-known/oauth-protected-resource/mcp
curl --fail https://ted.pepicrft.me/.well-known/oauth-authorization-server
curl --fail https://ted.pepicrft.me/.well-known/mcp/server-card.json
curl --fail https://ted.pepicrft.me/auth.md
```

Then register an anonymous agent, exchange its service assertion for an access token scoped only to `mcp`, initialize the Model Context Protocol connection, revoke the token, and confirm the next request returns `401 Unauthorized`. Finally, configure the Telegram webhook with Telegram's `secret_token` set to `TELEGRAM_WEBHOOK_SECRET` and send `/start`, `/goal`, `/checkin`, and `/today` from a real account.
