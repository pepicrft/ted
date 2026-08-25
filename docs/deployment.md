# Deploying Ted to Indie

Ted is reconciled from the `main` branch of `pepicrft/ted`. The Indie repository owns the source, image automation, runner, and production release declarations. The Ted repository owns the application, container, chart, and production values.

## Required secret record

Create an Infisical item named `ted` with these fields before enabling reconciliation:

| Field | Purpose |
| --- | --- |
| `POSTGRES_PASSWORD` | Password for the application database user. |
| `SECRET_KEY_BASE` | Phoenix cookie and message-signing secret. Generate it with `mise exec -- mix phx.gen.secret`. |
| `AGENT_AUTH_PRIVATE_KEY_PEM` | Stable private signing key in Privacy-Enhanced Mail format for service identity assertions. |

Generate the service signing key with OpenSSL:

```sh
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072
```

Here, RSA means the [Rivest-Shamir-Adleman public-key system](https://www.rfc-editor.org/rfc/rfc8017). Keep the complete output, including its header and footer, in `AGENT_AUTH_PRIVATE_KEY_PEM`.

The existing `kubernetes` secret item supplies the GitHub Container Registry pull username and token. The cluster object-storage controller creates the database backup credential after the bucket claim is reconciled.

Ted does not use an administrative application key. Agents register through the auth.md `service_auth` flow, and a person must claim the registration before Ted issues a scoped credential.

Access tokens expire after one hour by default. Agents refresh them by exchanging the service identity assertion again. `TED_AGENT_AUTH_ASSERTION_TTL_SECONDS` controls how long that assertion remains exchangeable. Keep the default one-day lifetime for interactive connections; a continuously running bot can use a longer rotation window when its assertion is stored in a dedicated secret manager and its registration can be revoked operationally.

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

Then register an agent with `service_auth`, complete the user claim, exchange its service assertion for an access token bound to the Model Context Protocol resource, initialize the connection, revoke the token, and confirm the next request returns `401 Unauthorized`.
