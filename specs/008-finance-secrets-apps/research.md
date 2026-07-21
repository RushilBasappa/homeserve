# Phase 0 — Research: Finance & Secrets (Actual + Vaultwarden + Sure)

The technical decisions behind Phase 7a and why they were made. Each app is off-the-shelf and
standalone; the "research" is confirming images, ports, data layout, lockdown, and data-preservation
paths so the stacks are reproducible and correct. Facts verified against upstream docs/GitHub on
2026-07-21 — re-check version tags at deploy (Diun/Phase-10 intent).

---

## R1 — Vaultwarden (passwords)

**Decision.** Run `vaultwarden/server:1.36.0-alpine` as a single container on the Dell, HTTP on
**:80**, data folder `/data` on the `vaultwarden-data` named volume, fronted by Traefik at
`vaultwarden.ragnaforge.xyz`. Lock it down: `SIGNUPS_ALLOWED=false`, Argon2-hashed `ADMIN_TOKEN`.

**Rationale.**
- **Image/port**: `vaultwarden/server` is the canonical image; in Docker it listens on **:80** (not
  8000), so the Traefik label is `loadbalancer.server.port=80`. Pin `1.36.0` (2026-05-03) — verify at
  <https://github.com/dani-garcia/vaultwarden/releases>; never `latest`.
- **Data folder `/data`** holds `db.sqlite3` (+ `-wal`/`-shm`), `attachments/`, `sends/`,
  `rsa_key.pem`/`rsa_key.pub.pem` (JWT signing keys), `config.json` (/admin-saved settings), and a
  disposable `icon_cache/`. All of it lives on the Dell (golden rule; FR-004).
- **End-to-end encryption (FR-001 context)**: Vaultwarden implements the Bitwarden zero-knowledge
  protocol — vault items are encrypted/decrypted **client-side** with a key derived from the master
  password; the server stores only ciphertext and never receives the master password in usable form.
  This is why master-password loss is unrecoverable (spec edge case) and why the encrypted store is
  the thing to preserve/back up.
- **Lockdown (FR-003, SC-002)**:
  - `DOMAIN=https://vaultwarden.ragnaforge.xyz` — required so WebAuthn/attachments/websocket URLs are
    correct (inlined literal; not a secret).
  - `SIGNUPS_ALLOWED=false` — no open registration. For a **restored** vault this is set from the
    start; for a **fresh** start, bring up once with `SIGNUPS_ALLOWED=true`, create the account(s),
    then flip to `false` and redeploy (documented in the runbook). `INVITATIONS_ALLOWED=true`
    (default) still lets the operator invite household members with signups closed; optionally scope
    with `SIGNUPS_DOMAINS_WHITELIST`.
  - `ADMIN_TOKEN` — an **Argon2 PHC hash** (not plaintext). Generate with
    `docker run --rm -it vaultwarden/server /vaultwarden hash` → `$argon2id$v=19$m=…`. In the compose
    `environment:` block **every `$` must be doubled to `$$`**; in `.mise.toml` it is a plain string
    (paste verbatim). Sourced from `mise` as `VAULTWARDEN_ADMIN_TOKEN`. If left unset, `/admin` is
    disabled entirely — also an acceptable lock-down, but we keep the gated admin panel.
- **Websockets**: the old **port 3012 was removed** (v1.31.0) and folded into the main :80 port
  (`ENABLE_WEBSOCKET=true` default). **Do not publish 3012.** Traefik forwards the WebSocket
  `Upgrade`/`Connection` headers to `/notifications/hub` automatically — no extra router/label.
- **Liveness**: `GET /alive` (unauthenticated) for the Docker/assert healthcheck.

**Alternatives considered.** Official Bitwarden `self-host` (far heavier: SQL Server + multiple
services — rejected for the 7.5 GB Dell); Vaultwarden with MySQL/Postgres backend (unnecessary — the
default SQLite is right for one household and keeps preservation to a single-folder copy).

**Data preservation (FR-002).** Straight `/data`-folder restore into `vaultwarden-data`: at minimum
`db.sqlite3` + `rsa_key.*` + `attachments/` (add `sends/` + `config.json` for full continuity).
**Stop the container first**, and **delete any stale `db.sqlite3-wal`** before starting to avoid WAL
mismatch corruption. The DB auto-migrates forward on start; do not downgrade the binary below the
DB's schema. If nothing was preserved, the fresh-start path (above) applies.

---

## R2 — Actual Budget (budgeting)

**Decision.** Run `actualbudget/actual-server:26.7.0-alpine` as a single container on the Dell, HTTP
on **:5006**, data folder `/data` on the `actual-data` volume, fronted by Traefik at
`actual.ragnaforge.xyz`. **No container secret** — the server login password is set in-app on first
run.

**Rationale.**
- **Image/port**: `actualbudget/actual-server` (the `actualbudget/actual-server` repo was archived
  Feb 2025; development moved into the `actualbudget/actual` monorepo but the **image name is
  unchanged**). Port `5006` (`ACTUAL_PORT` default) → `loadbalancer.server.port=5006`. Pin `26.7.0`
  (CalVer year.month, 2026-07-02) — verify at <https://github.com/actualbudget/actual/releases>.
- **Data folder `/data`** auto-creates `server-files/` (`account.sqlite` — server passwords,
  sessions, file metadata) and `user-files/` (the budget files as binary/encrypted blobs). On the
  Dell (FR-007).
- **Plain HTTP behind Traefik**: leave `ACTUAL_HTTPS_KEY`/`ACTUAL_HTTPS_CERT` **unset** → Actual
  serves plain HTTP on 5006 and Traefik terminates TLS (documented reverse-proxy setup). Optionally
  set `ACTUAL_TRUSTED_PROXIES` to the Docker/Traefik range if header/client-IP handling is needed
  (not required for the default password login). Bump `ACTUAL_UPLOAD_*` limits only if large-file
  sync errors appear.
- **Health**: no official `/health` endpoint documented — use a root-`GET :5006` 200 as a convention
  for the Docker healthcheck (flagged as convention, not a guaranteed API).

**Alternatives considered.** Running Actual's TLS directly (rejected — the edge already terminates
TLS; double-TLS is needless). End-to-end-encrypted budget files (an in-app option; orthogonal to
this phase — the server stores the blobs either way).

**Data preservation (FR-006).** Two independent paths, documented in the runbook:
1. **Volume restore (verbatim)** — restore the whole `/data` (both `server-files/` incl.
   `account.sqlite` and `user-files/`) into `actual-data`; preserves users, sessions, and every
   budget exactly.
2. **In-app `.zip` export/import (per budget)** — export a budget from the client, import into the
   fresh server via *Import → Actual*. Use if only one budget is moving or the raw volume isn't
   available. End-to-end-encrypted budgets need their encryption password on import.
If nothing was preserved, a new budget is created cleanly in-app.

---

## R3 — Sure (net-worth / wealth tracking; Maybe Finance fork)

**Decision.** Run the **`we-promise/sure`** fork (AGPLv3) as a **four-service** stack on the Dell —
`web` (`ghcr.io/we-promise/sure:stable`, Rails/Puma **:3000**) + `worker` (same image, `bundle exec
sidekiq`) + `db` (`postgres:16`) + `redis` (`redis:7-alpine`) — fronted by Traefik on `web` at
`sure.ragnaforge.xyz`. State on the Dell: `sure-pgdata`, `sure-storage`, `sure-redis`.

**Rationale.**
- **Fork identity**: `we-promise/sure` is the primary actively-maintained community fork of the
  archived `maybe-finance/maybe` (renamed "Sure"; explicitly *not affiliated with Maybe Finance Inc.*;
  AGPLv3). Repo/compose/env verified: <https://github.com/we-promise/sure>.
- **Topology (FR-009)**: the official `compose.example.yml` runs `web` + `worker` + `db` + `redis`
  (plus an optional `backup` profile we omit — Phase 10 owns backups). **Redis is required** — this
  fork uses **Sidekiq on Redis** for background jobs (it did *not* move to GoodJob-on-Postgres).
  Requirements: PostgreSQL >9.3, Redis >5.4.
- **Port/health**: `web` binds `0.0.0.0:3000` (`EXPOSE 3000`) → `loadbalancer.server.port=3000`;
  Rails health at **`GET /up`** (`rails/health#show`). The upstream compose defines no `web`
  healthcheck, so we **add one** hitting `/up:3000` (used by Traefik/Docker and the quickstart).
- **Env (FR-016)**:
  - `SECRET_KEY_BASE` — **required**; generate `openssl rand -hex 64`; from `mise` as
    `SURE_SECRET_KEY_BASE` (container secret → forwarded to Periphery).
  - `SELF_HOSTED=true` — enables self-hosting features (note: `SELF_HOSTED`, **not**
    `SELF_HOSTING_ENABLED`). `RAILS_ENV=production` is baked into the image.
  - DB: `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` on `db`; `DB_HOST=db`, `DB_PORT=5432`
    on web/worker. The password is `mise`'s `SURE_POSTGRES_PASSWORD` (container secret → forwarded).
  - `REDIS_URL=redis://redis:6379/1`.
  - `ONBOARDING_STATE` — `open` to create the first account, then set `closed` (or `invite_only`)
    and redeploy — the finance-side analogue of Vaultwarden's signup lockdown.
  - **TLS-behind-proxy**: leave `RAILS_FORCE_SSL=false` and set **`RAILS_ASSUME_SSL=true`** (Traefik
    terminates TLS; documented). No Rails host-authorization allowlist was found, so container-to-
    container HTTP from Traefik needs no hosts allowlist. `APP_DOMAIN=sure.ragnaforge.xyz` for email
    link generation (inlined literal).
  - Keep the upstream `dns: [8.8.8.8, 1.1.1.1]` on web/worker (avoids an IPv6 resolution hang on the
    free Yahoo-Finance market-data sync).
- **Migrations on boot (FR-010)**: the `web` entrypoint (`bin/docker-entrypoint`) runs
  `./bin/rails db:prepare` automatically **for the `web`/`rails server` command** — it creates and
  migrates the DB on start, **no separate one-shot needed**. The `worker` (sidekiq) does **not**
  migrate; it relies on `web` having prepared the schema. Both `web` and `worker` use
  `depends_on: { db: service_healthy, redis: service_healthy }`; db health = `pg_isready`, redis =
  `redis-cli ping`. So a cold deploy self-migrates and comes up healthy (SC-004).
- **Volumes (FR-011)**: `sure-pgdata → /var/lib/postgresql/data` (**must** persist — the DB);
  `sure-storage → /rails/storage` (ActiveStorage uploads; **shared by web+worker**); `sure-redis →
  /data` (optional — Sidekiq queue only).
- **Works without external keys**: optional integrations are off by default — AI
  (`OPENAI_ACCESS_TOKEN`), market data (defaults to **free** `yahoo_finance`; `twelve_data` needs a
  key), SMTP, OIDC, S3/R2 storage. None are required for the trial.

**Alternatives considered.** Upstream `maybe-finance/maybe` directly (archived/unmaintained — the
fork is the live path); Firefly III (a different, mature self-hosted finance tool — but PLAN.md
Phase 7a prescribes Sure specifically for the Actual-vs-Sure trial, so it is not substituted here).

**Image-tag caveat (see plan Complexity Tracking).** Only a rolling `:stable` GHCR tag is confirmed;
pin `stable@sha256:<digest>` for reproducibility (seerr-style exception) and let Diun watch releases.

---

## R4 — Wiring, secrets & exposure (cross-cutting)

**No inter-app wiring.** Unlike the Phase-5 servarr mesh, the three apps are **standalone** — none
talks to another. The only intra-stack coupling is Sure's `web`/`worker` → `db`/`redis`, handled by
Compose `depends_on` health conditions (not a plane-3 play). Consequently there is **no** cross-app
`configure/wire.yml`; the only optional plane-3 artifact is a **security assert** for Vaultwarden
(`/alive` up + signups closed), and health for Actual/Sure is validated by the quickstart.

**Secrets (FR-016).** Three container-referenced secrets, added as placeholders to
`.mise.toml.example` and forwarded to the Periphery env (so a Periphery-run compose resolves `${VAR}`):

| Var | Used by | Generate |
|---|---|---|
| `VAULTWARDEN_ADMIN_TOKEN` | vaultwarden `ADMIN_TOKEN` | `vaultwarden hash` (Argon2 PHC); **`$$`-escape in compose** |
| `SURE_SECRET_KEY_BASE` | sure web + worker | `openssl rand -hex 64` |
| `SURE_POSTGRES_PASSWORD` | sure db + web + worker | `openssl rand -hex 32` |

**Actual needs no container secret** — its login password is set in-app on first run and stored in
`account.sqlite`. Non-secret config (`DOMAIN`, `APP_DOMAIN`, `RAILS_ASSUME_SSL`, ports) is **inlined
as literals** in each compose, because Komodo does not interpolate `[[VAR]]` into git-pulled compose
(established house rule).

**Exposure (FR-015, SC-006).** All three are HTTP UIs behind the Phase-3 Traefik + wildcard cert at
`*.ragnaforge.xyz`, which AdGuard resolves to the Dell internally. **No host `ports:`** are published
(Postgres/Redis stay internal on the `sure` network; the web UIs are reached only via Traefik) and
**no router port-forward** is added — remote access is via the existing VPN. Given these hold
passwords and finances, public exposure is explicitly disallowed and audited (SC-006).

---

## R5 — Homepage & conventions

**Homepage (FR-013).** Add three tiles to the **Apps** group in `stacks/homepage/compose.yaml`
(`vaultwarden.png`, `actual.png`, `sure.png` icons; `href` to each `https://<app>.ragnaforge.xyz`).
**No native widgets** are wired — Homepage has no first-class Vaultwarden/Actual/Sure summary widget
that works without extra admin APIs, and the spec asks for tiles (a widget only "where supported").
Tiles satisfy FR-013/SC-005.

**Conventions.** One name everywhere (dir = stack = subdomain = Homepage entry): `vaultwarden`,
`actual`, `sure`. Grow the `docs/CONVENTIONS.md` URL table (three new `<app>.ragnaforge.xyz`) and note
the internal-only container ports (80 / 5006 / 3000, plus Sure's internal Postgres 5432 / Redis 6379
— **none published**). Deploy order and the one-time data-restore steps go in
`docs/runbooks/phase7a-finance-secrets.md`.

---

## Summary of decisions

| # | Decision | Key rationale |
|---|---|---|
| R1 | Vaultwarden `1.36.0-alpine`, :80, `/data` on Dell, signups off + Argon2 admin token | Canonical, zero-knowledge, tiny; lockdown = LAN-safe password server |
| R2 | Actual `26.7.0-alpine`, :5006, `/data` on Dell, plain HTTP behind Traefik, no secret | Local-first budgeting; login set in-app; simplest single container |
| R3 | Sure `we-promise/sure:stable`, web+worker+db(pg16)+redis, :3000, `/up`, self-migrates | The prescribed Maybe fork; Rails needs PG+Redis+Sidekiq; cold-deploy healthy |
| R4 | 3 mise secrets; no inter-app wiring; LAN/VPN-only, no host ports/forward | Reproducible + never public — passwords/finance are sensitive |
| R5 | 3 Homepage tiles (no widgets); grow CONVENTIONS; new runbook | Consistent front door; one name everywhere |
