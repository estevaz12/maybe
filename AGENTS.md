# Agent and automation notes

This file helps AI coding agents and automation bootstrap, verify changes, and find operational hooks in this repository.

## Stack

- Ruby on Rails 7.2, PostgreSQL, Redis (Sidekiq), Node.js for JS lint/format (Biome)
- Hotwire (Turbo, Stimulus), Tailwind CSS v4, Minitest + fixtures

## Environment

- **Ruby:** Must match [`.ruby-version`](.ruby-version) (see also [`Gemfile`](Gemfile)). With [mise](https://mise.jdx.dev/), run `mise trust` in the repo root once, then `mise install`.
- **PostgreSQL:** Required for the app and tests; use a recent stable release (CI uses the official `postgres` image).
- **Redis:** Required for `bin/dev` (Sidekiq worker). Default dev URL is typically `redis://127.0.0.1:6379/1` unless overridden in `.env.local`.
- **Node.js:** Required for `npm run lint` / `npm run format` (Biome). CI uses Node 20.

## First-time setup

1. `cp .env.local.example .env.local` and adjust if needed.
2. `bin/setup` (Bundler, `db:prepare`, clears logs, `npm install` when `package.json` is present).
3. `bin/dev` — starts Rails, Tailwind watcher, and Sidekiq (ensure PostgreSQL and Redis are running).

## Verify changes

| Scope                                    | Commands                                                                                                                         |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Full suite (before merge / large change) | `bin/rails test`, then `bin/rails test:system` if UI changed; `bin/rubocop -f github`; `npm run lint`; `bin/brakeman --no-pager` |
| Single file / line                       | `bin/rails test path/to/test_file.rb` or `bin/rails test path/to/test_file.rb:42`                                                |
| Ruby only                                | `bin/rubocop path/to/file.rb`                                                                                                    |
| JavaScript only                          | `npm run lint -- path/to/file.js`                                                                                                |

Coverage (optional): `COVERAGE=true bin/rails test` — SimpleCov is configured in [`test/test_helper.rb`](test/test_helper.rb).

`npm test` runs `bin/rails test` for tooling that expects an npm test script.

## Health and observability

- **Load balancer / uptime:** HTTP `GET /up` — Rails health check (200 when the app boots cleanly). See [`config/routes.rb`](config/routes.rb).
- **Production:** Error tracking and performance tooling are configured via gems (e.g. Sentry, Skylight, Logtail) when credentials and env are set — see [`Gemfile`](Gemfile) and deployment docs.

## Project conventions

- [.cursor/rules/](.cursor/rules/) — Cursor rules; start with [`project-conventions.mdc`](.cursor/rules/project-conventions.mdc) and [`project-design.mdc`](.cursor/rules/project-design.mdc).
- [CLAUDE.md](CLAUDE.md) — command reference and PR checklist.

## Optional: pre-commit

If you use [pre-commit](https://pre-commit.com/), install hooks from the repo root: `pre-commit install`. Config: [`.pre-commit-config.yaml`](.pre-commit-config.yaml).

## Optional: Cursor MCP

Project MCP config: [`.cursor/mcp.json`](.cursor/mcp.json). Add servers there (e.g. Postgres, browser) for your environment; do not commit secrets.
