# Ted

Ted is an open, headless coach for strength training and nutrition. It keeps structured objectives, check-ins, meals, workouts, and versioned plans, then uses the recorded trend to suggest the next useful action.

The name and warm coaching spirit reference [Ted Lasso](https://tv.apple.com/us/show/ted-lasso/umc.cmc.vtoh0mn0xn7t3c643xqonfzy). This project is independent and is not affiliated with or endorsed by Apple, Warner Bros., or the creators of the series.

## What it does

- Tracks several prioritized objectives, including fat loss, muscle gain, body recomposition, strength, and consistency.
- Produces a daily training, nutrition, and recovery recommendation from the active plan and current readiness.
- Suggests concrete meals that respect recorded dietary preferences, available time, known avoided ingredients, and the active objective, with evidence and limitations in every response.
- Reviews trends over a defined window, records confidence and rationale, and changes at most one major plan variable at a time.
- Pauses progression when a check-in contains a meaningful pain signal.
- Exposes one shared operation catalog through an [OpenAPI](https://www.openapis.org/)-described web interface and a [Model Context Protocol](https://modelcontextprotocol.io/) server.
- Can optionally receive commands as a Telegram bot.
- Implements the [auth.md](https://workos.com/auth-md/docs) `service_auth` registration and user-claim flow. Agents receive only short-lived, scoped bearer credentials after the person confirms access.

The research behind the first coaching rules, their limitations, and the exact implementation mapping live in [docs/evidence.md](docs/evidence.md).

## Run locally

Install [Mise](https://mise.jdx.dev/) and PostgreSQL, then run:

```sh
mise install
mise exec -- mix setup
mise exec -- mix phx.server
```

Mise assigns a stable address and database to each Git worktree. Print the address with:

```sh
mise exec -- printenv TED_URL
```

Useful routes:

- `/` redirects to the interactive operation reference.
- `/docs` provides the interactive operation reference.
- `/openapi.json` provides the machine-readable web interface description.
- `/auth.md` explains agent registration.
- `/.well-known/oauth-protected-resource` and `/.well-known/oauth-authorization-server` provide authorization discovery.
- `/mcp` serves the Model Context Protocol.
- `/telegram/webhook` receives Telegram updates when the optional integration is configured.
- `/health` reports service and database readiness.

Reset and seed the development database with two isolated example people:

```sh
mise exec -- mix ecto.reset
```

Run the full local verification suite with:

```sh
mise exec -- mix precommit
```

## Important configuration

Production reads `TED_*` environment variables. Required secrets are the database address, Phoenix signing secret, and auth.md service-assertion signing key. Ted does not have an administrative application key. Access is granted through auth.md and bound to the authenticated person.

The Telegram integration is optional. Set `TED_TELEGRAM_BOT_TOKEN` and `TED_TELEGRAM_WEBHOOK_SECRET` only when enabling it.

## Deploy your own instance

Ted is designed to be self-hosted. The repository includes a production container and a Helm chart in `deploy/helm/ted`.

Create a values file for your installation and set at least:

```yaml
host: ted.example.com
publicOrigin: https://ted.example.com

ingress:
  enabled: true
  className: nginx
  tlsSecretName: ted-example-com-tls

extraEnv:
  TED_ALLOWED_MCP_ORIGINS: https://ted.example.com
```

Provide the required database, Phoenix, and agent-signing secrets through your cluster's secret manager. Then install the chart:

```sh
helm upgrade --install ted deploy/helm/ted \
  --namespace ted \
  --create-namespace \
  --values path/to/your-values.yaml
```

The chart can create a PostgreSQL cluster, ingress, certificate integration, external secret projections, and scheduled backups. Review `deploy/helm/ted/values.yaml` for every setting. [docs/deployment.md](docs/deployment.md) documents one production integration as a worked example, including required secrets and readiness checks.

## Health boundary

Ted supports ordinary habit, nutrition, and strength coaching. It is not a medical device, does not diagnose illness or prescribe treatment, and must not recommend extreme restriction. Persistent, severe, or worsening pain, suspected disordered eating, pregnancy, and other health concerns belong with a qualified professional.

## License

Ted uses the [GNU Affero General Public License version 3 or later](https://www.gnu.org/licenses/agpl-3.0.html). You may run a hosted service and charge for it. If you modify Ted and let people interact with that modified version over a network, the license requires you to offer those users the corresponding source code.
