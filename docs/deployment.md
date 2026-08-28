# Self-hosting notes

The [README](../README.md#-self-host-ted) is the primary deployment guide. This page records the additional decisions a production operator should make before exposing Ted on a public address.

## Secret ownership

Ted requires three stable secrets:

| Secret | Purpose |
| --- | --- |
| PostgreSQL password | Authenticates the application database user. |
| `TED_SECRET_KEY_BASE` | Signs Phoenix cookies and messages. Generate it with `mise exec -- mix phx.gen.secret`. |
| `TED_AGENT_AUTH_PRIVATE_KEY_PEM` | Signs service identity assertions used by agent registration. |

Generate the assertion key with OpenSSL:

```sh
openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:3072 \
  -out ted-agent-auth-private-key.pem
```

RSA refers to the [Rivest-Shamir-Adleman public-key system](https://www.rfc-editor.org/rfc/rfc8017). Store the complete Privacy-Enhanced Mail document, including its header and footer. Keep both signing secrets stable across releases and back them up separately from the database.

Ted has no administrative application key. A client registers through the auth.md or authorization-code flow, and a person must confirm access before Ted issues a scoped credential.

## Database

The chart can create a PostgreSQL cluster through [CloudNativePG](https://cloudnative-pg.io/). Operators using an external database should disable `postgres.enabled`, provide `TED_DATABASE_URL`, and make the database certificate-authority secret available at the path configured by `TED_DATABASE_CERTIFICATE_AUTHORITY_FILE`.

Transport encryption is enabled by default in production. Disable it only when the database connection stays inside a trusted private network and the risk is understood.

Back up the database on a schedule, retain more than one restore point, and test a restoration before relying on those backups. The chart can create CloudNativePG scheduled backups when `postgres.backup.enabled` is true and the required object-store integration is available.

## Email verification

New accounts must verify their email address before approving an agent or client. Configure `TED_EMAIL_FROM_ADDRESS`, `TED_SMTP_RELAY`, and `TED_SMTP_PORT` for a relay reachable from the application network. Test delivery before inviting a person to claim an account.

Claim links expire after ten minutes by default. `TED_AGENT_AUTH_CLAIM_ATTEMPT_TTL_SECONDS` can extend that window when a person may respond asynchronously. Every registration response advertises the exact remaining lifetime through `claim.expires_in`.

## Credential lifetime

Access tokens expire after one hour by default. An auth.md agent obtains another token by exchanging its service identity assertion again. `TED_AGENT_AUTH_ASSERTION_TTL_SECONDS` controls how long that assertion remains exchangeable and defaults to one day.

Use a longer assertion lifetime only when the assertion is stored in a dedicated secret manager, registrations can be revoked operationally, and the client cannot complete a new claim ceremony when unattended.

## Publication order

1. Install the required database, ingress, certificate, and secret-management controllers.
2. Create the application and database secrets.
3. Publish or select an immutable Ted container image.
4. Install the chart with installation-specific values.
5. Wait for PostgreSQL, the migration container, the application deployment, ingress, and certificate to become ready.
6. Complete a real account claim and client authorization.
7. Enable and verify database backups.

## Readiness checks

Replace the example host with the address of the installation:

```sh
curl --fail https://coach.example.com/health
curl --fail https://coach.example.com/.well-known/oauth-protected-resource/mcp
curl --fail https://coach.example.com/.well-known/oauth-authorization-server
curl --fail https://coach.example.com/.well-known/mcp/server-card.json
curl --fail https://coach.example.com/auth.md
```

Then register an agent, complete the claim, exchange its service assertion for a token bound to the Model Context Protocol resource, initialize a connection, revoke the token, and confirm the next protected request is rejected.
