# ⚽ Ted

> A self-hosted, headless coach for strength training and nutrition.

Ted turns objectives, check-ins, meals, workouts, and recovery signals into a plan you can adjust as life happens. It tracks the facts, reviews trends over time, and suggests the next useful action without pretending that one plan fits everyone.

Your installation, accounts, and coaching records stay in infrastructure you control. Ted does not require an administrator key or a model-provider key. Connect directly through the [Model Context Protocol](https://modelcontextprotocol.io/), use a compatible client or bot such as Hermes or OpenClaw, or follow the [auth.md agent registration protocol](https://workos.com/auth-md/docs).

[![Ted checks](https://github.com/pepicrft/ted/actions/workflows/ted.yml/badge.svg)](https://github.com/pepicrft/ted/actions/workflows/ted.yml)

## ✨ What Ted does

- 🎯 Tracks prioritized objectives for fat loss, muscle gain, body recomposition, strength, and consistency.
- 🗓️ Builds a daily training, nutrition, and recovery recommendation from the active plan and current readiness.
- 🥗 Suggests concrete meals using dietary preferences, available time, avoided ingredients, and the active objective.
- 📈 Reviews a defined trend window instead of reacting to one measurement.
- 🧾 Stores the observations, confidence, rationale, and evidence behind every plan-level adjustment.
- 🔧 Changes at most one major plan variable during a review so the effect remains understandable.
- 🛑 Stops progression when a check-in contains a meaningful pain signal.
- 🔐 Keeps every profile, objective, log, and plan isolated to its authenticated person.

Ted is deliberately headless. The small browser surface exists for account claims, client authorization, and operation documentation. The coaching experience belongs in the client you choose.

## 🧠 How coaching works

1. **Set the destination.** Record one or more measurable objectives and their priority.
2. **Describe the constraints.** Add training experience, available days, equipment, dietary preferences, and other relevant facts.
3. **Log what happened.** Record body-weight and readiness check-ins, meals, and completed workouts.
4. **Ask for today.** Ted combines the active plan with recent readiness to return the next training, nutrition, and recovery actions.
5. **Review the trend.** After a meaningful window, Ted explains whether the plan should stay steady or change one variable.

The rules and meal suggestions are deterministic and traceable. [The evidence ledger](docs/evidence.md) connects each implemented rule to its supporting research and records important limitations.

## 🔌 Choose how to use Ted

| Interface | Best for | Starting point |
| --- | --- | --- |
| [Model Context Protocol](https://modelcontextprotocol.io/) | Claude, Hermes, OpenClaw, and other compatible clients or bots | `https://coach.example.com/mcp` |
| [auth.md](https://workos.com/auth-md/docs) | Agents that register on a person's behalf | `https://coach.example.com/auth.md` |
| [OpenAPI](https://www.openapis.org/) web interface | Custom applications and direct integration | `https://coach.example.com/openapi.json` |

### Model Context Protocol clients

Point a compatible client at `/mcp`. Ted publishes protected-resource and authorization-server discovery, supports dynamic client registration, and asks the person to sign in and approve the requested scopes. Access tokens are short lived, resource bound, and limited to that person's coaching records.

The shared operation catalog includes tools to:

- read or update a coaching profile;
- set and list objectives;
- record check-ins, meals, and workouts;
- ask for a preference-aware meal suggestion;
- build, read, and review a plan;
- read today's actions and recent progress.

### auth.md agents

An agent starts at `/auth.md`, registers with the person's email address, and receives a claim link plus a six-digit code. The person opens the link, signs in or creates an account, verifies the email address, and enters the code. Ted issues scoped credentials only after that confirmation.

## 🚀 Run Ted locally

### Requirements

- [Mise](https://mise.jdx.dev/)
- [PostgreSQL](https://www.postgresql.org/)
- Git

Install the pinned Erlang and Elixir versions, prepare the database, and start the server:

```sh
git clone https://github.com/pepicrft/ted.git
cd ted
mise install
mise exec -- mix setup
mise exec -- mix phx.server
```

Mise gives every Git worktree a stable development address and isolated databases. Print the assigned address with:

```sh
mise exec -- printenv TED_URL
```

The seed data represents two people with separate profiles, objectives, logs, and plans. Reset it at any time with:

```sh
mise exec -- mix ecto.reset
```

Run the complete local verification suite with:

```sh
mise exec -- mix precommit
```

## 🏠 Self-host Ted

The repository includes a production container and a [Helm](https://helm.sh/) chart. The chart is the recommended starting point because it runs database migrations before the application, configures readiness checks, and can create a PostgreSQL cluster.

### Production requirements

- A [Kubernetes](https://kubernetes.io/) cluster and Helm 3.
- A public secure address such as `coach.example.com`.
- An ingress controller and certificate management for that address.
- [CloudNativePG](https://cloudnative-pg.io/) when the chart should create PostgreSQL.
- A mail relay reachable from the cluster. Ted uses it for one-time email verification links.
- Three secrets: a database password, a Phoenix signing secret, and a stable agent-assertion private key.

### 1. Generate the secrets

Generate the Phoenix signing secret:

```sh
mise exec -- mix phx.gen.secret
```

Generate a 3,072-bit private key for service identity assertions:

```sh
openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:3072 \
  -out ted-agent-auth-private-key.pem
```

Here, RSA refers to the [Rivest-Shamir-Adleman public-key system](https://www.rfc-editor.org/rfc/rfc8017). Keep both generated values private and back them up through your secret manager.

### 2. Create the namespace and secret objects

The commands below show the chart's default names. Replace every placeholder, and use a database password that is safe to include in a database address or encode its reserved characters first.

```sh
kubectl create namespace ted

kubectl --namespace ted create secret generic ted-postgres-app \
  --from-literal=username=ted \
  --from-literal=password='replace-with-a-random-database-password'

kubectl --namespace ted create secret generic ted-app-env \
  --from-literal=TED_DATABASE_URL='ecto://ted:replace-with-a-random-database-password@ted-postgres-rw/ted_prod' \
  --from-literal=TED_SECRET_KEY_BASE='replace-with-the-generated-phoenix-secret' \
  --from-file=TED_AGENT_AUTH_PRIVATE_KEY_PEM=./ted-agent-auth-private-key.pem
```

The chart can project these values from an external secret manager instead. Set `externalSecrets.enabled: true` and configure `externalSecrets.secretStoreRef` plus the field mappings in your values file.

### 3. Create a values file

Save a file such as `ted-values.yaml`:

```yaml
host: coach.example.com

ingress:
  enabled: true
  className: nginx
  tlsSecretName: coach-example-com-tls

extraEnv:
  TED_ALLOWED_MCP_ORIGINS: https://coach.example.com
  TED_EMAIL_FROM_ADDRESS: ted@coach.example.com
  TED_EMAIL_FROM_NAME: Ted
  TED_SMTP_RELAY: mail-relay.default.svc.cluster.local
  TED_SMTP_PORT: "587"
```

Review [the complete chart values](deploy/helm/ted/values.yaml) before installing. In particular, choose storage, resource limits, database backups, ingress annotations, and secret integration appropriate for your cluster.

### 4. Install or upgrade

```sh
helm upgrade --install ted deploy/helm/ted \
  --namespace ted \
  --create-namespace \
  --values ted-values.yaml
```

The deployment waits for PostgreSQL, applies every migration through `Ted.Release.migrate`, and starts the application only after the migration succeeds.

### 5. Verify the installation

```sh
kubectl --namespace ted rollout status deployment/ted

curl --fail https://coach.example.com/health
curl --fail https://coach.example.com/.well-known/oauth-protected-resource/mcp
curl --fail https://coach.example.com/.well-known/oauth-authorization-server
curl --fail https://coach.example.com/auth.md
```

Then connect a client to `https://coach.example.com/mcp`, complete the browser authorization, and call `get_profile` to confirm that the authenticated account can reach its own records.

### Required production settings

| Setting | Purpose |
| --- | --- |
| `TED_DATABASE_URL` | PostgreSQL connection address. |
| `TED_SECRET_KEY_BASE` | Phoenix cookie and message-signing secret. |
| `TED_AGENT_AUTH_PRIVATE_KEY_PEM` | Stable private key used to sign agent identity assertions. |
| `TED_HOST` | Public host name. The chart sets this from `host`. |
| `TED_SCHEME` | Public address scheme. The chart sets this to `https`. |
| `TED_ALLOWED_MCP_ORIGINS` | Comma-separated browser origins allowed to call the Model Context Protocol endpoint. |
| `TED_EMAIL_FROM_ADDRESS` | Sender address for account verification. |
| `TED_SMTP_RELAY` | Mail relay host. |

Database transport encryption is enabled in production by default. Set `TED_DATABASE_CERTIFICATE_AUTHORITY_FILE` to the certificate-authority bundle for PostgreSQL, or set `TED_DATABASE_SSL=false` only for a trusted private connection where transport encryption is deliberately disabled.

All rate limits and credential lifetimes have production defaults and can be tuned through the settings in [config/runtime.exs](config/runtime.exs). Claim links last ten minutes, access tokens last one hour, and service identity assertions remain exchangeable for one day by default.

## 🩺 Health and safety boundary

Ted supports ordinary habit, nutrition, and strength coaching. It provides general educational suggestions, not medical or dietetic care. It does not diagnose illness, prescribe treatment, recommend extreme restriction, or present estimated food values as measurements.

Meaningful pain stops progression. Persistent, severe, or worsening pain, suspected disordered eating, pregnancy, kidney disease, and other relevant health concerns belong with a qualified professional. You remain responsible for checking allergens, medically restricted ingredients, exercise selection, and whether a suggestion is appropriate for your circumstances.

## 🛠️ Operate and develop Ted

Useful routes on every installation:

| Route | Purpose |
| --- | --- |
| `/` | Redirects to the interactive operation reference. |
| `/docs` | Interactive operation reference. |
| `/openapi.json` | Machine-readable operation document. |
| `/auth.md` | Agent registration instructions. |
| `/.well-known/oauth-protected-resource` | Protected-resource discovery. |
| `/.well-known/oauth-authorization-server` | Authorization-server discovery. |
| `/.well-known/mcp/server-card.json` | Model Context Protocol server description. |
| `/mcp` | Model Context Protocol endpoint. |
| `/health` | Application and database readiness. |

Recommended operational practices:

- Back up PostgreSQL and test restoration regularly.
- Keep the Phoenix secret and agent-signing key stable across deployments.
- Rotate exposed credentials and revoke affected access tokens.
- Put Ted behind secure transport and restrict direct access to the application port.
- Review logs and traces without recording claim tokens, access tokens, or passwords.
- Upgrade by applying database migrations before replacing the running application. The chart does this automatically.

## 📚 Project documentation

- [Evidence ledger](docs/evidence.md): research, limitations, and implementation rules.
- [Design reference](docs/design-reference.md): the visual principles behind the small browser surface.
- [`auth.md` controller](lib/ted_web/controllers/auth_markdown_controller.ex): the generated agent-registration document.
- [Operation schema](lib/ted_web/api_spec.ex): the shared web operation catalog.
- [Helm chart](deploy/helm/ted): production deployment resources and defaults.

## 🤝 Contributing

Issues and pull requests are welcome. Keep the web interface, operation document, Model Context Protocol tools, and auth.md workflow consistent when changing an operation. Every plan-level adjustment must retain its observations, confidence, rationale, and evidence.

Before opening a pull request:

```sh
mise exec -- mix precommit
```

## 💛 The name

The name and warm coaching spirit reference [Ted Lasso](https://tv.apple.com/us/show/ted-lasso/umc.cmc.vtoh0mn0xn7t3c643xqonfzy). This project is independent and is not affiliated with or endorsed by Apple, Warner Bros., or the creators of the series.

## 📄 License

Ted uses the [GNU Affero General Public License version 3 or later](https://www.gnu.org/licenses/agpl-3.0.html). You may operate the software yourself or offer it as a service. If you modify Ted and let people interact with that modified version over a network, the license requires you to offer those users the corresponding source code.
