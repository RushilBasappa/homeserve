# Contract: Wiring (intra-stack deps, data preservation, exposure)

Unlike the Phase-5 servarr mesh, **the three apps are standalone — none connects to another.** There
is therefore **no cross-app plane-3 wiring** to reproduce. What this contract pins is: the one
intra-stack dependency (Sure), the one-time data-preservation restore, the optional security assert,
and the invariants that keep these sensitive apps safe (no public exposure, no committed secrets).

## Edges

| # | Edge | Type | Reproduced by |
|---|---|---|---|
| 1 | **Sure `web`/`worker` → `db` + `redis`** | intra-stack dependency | Compose `depends_on: {condition: service_healthy}` + healthchecks |
| 2 | **Sure `web` → own DB schema** | boot-time migration | `bin/docker-entrypoint` runs `rails db:prepare` on `web` start |
| 3 | **Operator → existing vault / budget** | one-time data restore | manual volume restore into `vaultwarden-data` / `actual-data` (runbook) |
| 4 | **Homepage → each app** | linked tile (no widget) | inline `stacks/homepage/compose.yaml` tiles |
| 5 | *(none)* **app → app** | — | there is no inter-app connection in this phase |

## Edge 1 & 2 — Sure intra-stack dependency + self-migration

- **Ordering**: both `web` and `worker` declare
  `depends_on: { db: {condition: service_healthy}, redis: {condition: service_healthy} }`. Healthchecks:
  `db` = `pg_isready -U sure` (interval 5s, retries 5), `redis` = `redis-cli ping`. So the app services
  start only after PostgreSQL and Redis are ready (FR-010).
- **Migration**: the `web` entrypoint runs `./bin/rails db:prepare` automatically on start — creates and
  migrates the DB. **No separate one-shot migration job.** The `worker` (sidekiq) does not migrate; it
  relies on `web` having prepared the schema, so in normal `docker compose up` ordering `web` prepares
  first. A cold deploy therefore comes up healthy with **no manual step** (SC-004).
- **`web` health**: add a healthcheck hitting `GET http://localhost:3000/up` (Rails default) since the
  upstream compose omits one — Traefik and the quickstart both use it.

## Edge 3 — One-time data preservation (vault + budget)

This is a **one-time** operator action, not automated wiring (scheduled backups are Phase 10). Documented
step-by-step in `docs/runbooks/phase7a-finance-secrets.md`:

- **Vaultwarden**: **stop** the container, restore the pre-migration `/data` folder into `vaultwarden-data`
  (`db.sqlite3` + `rsa_key.*` + `attachments/`; optionally `sends/` + `config.json`), **delete any stale
  `db.sqlite3-wal`**, then start. Unlock with the master password → existing logins present, **0 loss**
  (FR-002, SC-001).
- **Actual**: restore the pre-migration `/data` (both `server-files/` and `user-files/`) into
  `actual-data` **or** import a per-budget `.zip` via *Import → Actual* in the client (FR-006, SC-003).
- **If nothing was preserved**: each app starts cleanly as a fresh instance (the guaranteed path);
  Vaultwarden creates the first account with `SIGNUPS_ALLOWED=true`, then flips to `false` and redeploys.

## Edge 4 — Homepage tiles

- Three linked tiles in the **Apps** group → `https://vaultwarden.ragnaforge.xyz`,
  `https://actual.ragnaforge.xyz`, `https://sure.ragnaforge.xyz`. **No native widgets** — none of the
  three exposes a first-class Homepage summary widget usable without extra admin APIs, and the spec asks
  for tiles (a widget only "where supported"). Tiles satisfy FR-013 / SC-005.

## Optional plane-3 assert — Vaultwarden lockdown (`stacks/vaultwarden/configure/setup.yml`)

The single security-critical check worth codifying (kept idempotent, GET-only — **never mutates the
vault**):

- Assert `GET https://vaultwarden.ragnaforge.xyz/alive` returns 200 (server live).
- Assert **registration is closed** — a `POST /api/accounts/register` (or equivalent) is refused while
  `SIGNUPS_ALLOWED=false`, so an unauthenticated stranger cannot register (FR-003, SC-002). **Fail loudly**
  if signup is unexpectedly open.
- Re-runs change nothing. Actual and Sure health are validated by the quickstart (`/up` for Sure; a
  root-200 for Actual) rather than a bespoke play — keeping custom code minimal (research R4).

## Invariants enforced here

- **No public exposure (FR-015, SC-006)**: no host `ports:` on any service (Sure's `db`/`redis` stay on
  the internal `sure` network), and **no** router port-forward. Remote access is via the existing VPN only.
  A password/finance server on the public internet is a critical failure — audited by SC-006.
- **No committed secrets (FR-016, SC-007)**: the 3 container secrets come from `mise`; Actual adds none.
  Grep the repo → **0** secret values (SC-007).
- **Golden rule (FR-017, SC-008)**: every volume is Dell-local; **0** state on the Mac or `/srv/nfs`.
- **Idempotency (SC-008)**: re-running the Vaultwarden assert or redeploying any stack **changes nothing**
  (Sure's `db:prepare` is convergent; no wiring to re-apply).
- **Stack isolation (FR-014, SC-009)**: stopping/removing any one stack leaves the other two reachable.
