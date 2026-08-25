# Ted development instructions

## Writing

- Avoid acronyms. When one is necessary, include its full name and a link to a website that explains the concept.

## Elixir

- Minimize explicit raising patterns and raising function variants. Prefer pattern matching on tagged return values and function heads so invalid states fail where they are introduced.
- Use Elixir's standard `JSON` module for JavaScript Object Notation encoding and decoding. Do not add or use Jason in application or test code.

## Tests

- Never modify global state from a test. This includes application environment changes such as `Application.put_env/3`.
- Pass configuration and dependencies directly to the code under test.
- Every Elixir test module must run with `async: true`.

## Worktrees

- Run development and test commands through `mise exec --`. Mise assigns every Git worktree a stable development instance, server port, test port, development database, and test database.
- Do not hardcode local ports or database names in application code, tests, documentation, or agent instructions. Read the generated `TED_*` environment variables or derive public addresses from `TedWeb.Endpoint`.

## Interface consistency

- Ted is primarily a headless service. Keep its [Representational State Transfer](https://developer.mozilla.org/en-US/docs/Glossary/REST) application programming interface, [Model Context Protocol](https://modelcontextprotocol.io/) server, and [auth.md agent registration](https://workos.com/auth-md) workflow consistent.
- Describe every [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) operation with [OpenAPI](https://www.openapis.org/) through [OpenApiSpex](https://github.com/open-api-spex/open_api_spex).
- Use the same operation names, request fields, response fields, authorization scopes, and behavior in the OpenAPI operation identifiers and Model Context Protocol tool names.
- When an operation changes, update and test the Hypertext Transfer Protocol route, OpenAPI document, and Model Context Protocol tool together.
- Treat Telegram credentials, service signing keys, provider assertions, claim tokens, and access tokens as secrets. Never place them in logs or response fields that do not explicitly issue a one-time credential.
- Keep `priv/repo/seeds.exs` representative of multiple people, objectives, and plans. End-to-end verification must prove that profiles, logs, objectives, and plans remain isolated by person through both the web interface and Model Context Protocol server.

## Coaching safety and evidence

- Every plan-level adjustment must cite the stored observations, confidence, rationale, and evidence used for the decision.
- Prefer a review window over reacting to one measurement. Change no more than one major plan variable per review.
- A meaningful pain signal stops progression. Do not diagnose illness, prescribe treatment, recommend extreme restriction, or present estimated food values as measurements.
- Keep `docs/evidence.md` synchronized with the rules encoded by the planner and reviewer.

## GitHub pull requests

- Do not use em dashes in comments or reviews.
- Write comments and reviews as if Pepicrft wrote them directly. Do not frame them as assistant output unless explicitly requested.
- Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) for pull request titles in the form `type(ted): summary`.
- Structure descriptions with the applicable headings `## What changed`, `## Why`, `## Root cause`, `## Approach`, `## Impact`, and `## Validation`.
- Use concise prose. Bullets are appropriate for concrete changes and validation, but the whole description should not be a terse file list.

## Web application verification

- Run the application locally and verify behavior with [headless Chrome](https://developer.chrome.com/docs/chromium/headless).
- Capture screenshots during verification.
- Include verification screenshots in the [GitHub pull request](https://docs.github.com/en/pull-requests) description. For fixes, include before and after screenshots.
