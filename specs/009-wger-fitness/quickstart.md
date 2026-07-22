# Quickstart — Validate the wger stack (SC-001…SC-009)

A runnable validation guide: bring the stack up via Komodo and confirm each success criterion. Not an
implementation guide — the compose, inline nginx.conf, and env live in `stacks/wger/compose.yaml`
(see [contracts/stack-inventory.md](./contracts/stack-inventory.md)); step-by-step bring-up and the
first-run admin-password change live in `docs/runbooks/wger.md`.

## Prerequisites

- Phase-3 edge live: Traefik + wildcard `*.ragnaforge.xyz` TLS + AdGuard (resolves `wger` → the Dell) +
  Homepage. Komodo Core + the Dell Periphery agent reachable.
- Secrets set in the gitignored `.mise.toml` (copied from `.mise.toml.example`):
  `WGER_SECRET_KEY` (`openssl rand -hex 50`), `WGER_POSTGRES_PASSWORD` (`openssl rand -hex 32`).
- Secrets forwarded to the Dell Periphery env: `make sync-secrets` + Periphery recreate (so a
  Periphery-run compose resolves `${VAR}` — see [[homeserve-ops-access]]).
- `komodo/stacks.toml` has the `wger` `[[stack]]` (server `ragnaforge-dell`); ResourceSync applied.

## Bring-up

Deploy from Komodo Core (manual — `webhook_enabled=false`): **DeployStack `wger`**. On a cold deploy the
order converges automatically: `db`+`cache` healthy → `web` migrates + collects static → `nginx` +
`celery_worker` → `celery_beat`. No manual `migrate`/`collectstatic` step.

Then, once (runbook): open the UI, log in as the bootstrapped `admin`, and **change the admin password
immediately** (the default is a documented weak credential).

## Validation scenarios

### SC-003 — Cold deploy comes up healthy, no manual steps 🎯 (the topology risk)
- In Komodo, confirm all six services reach **healthy/running**: `db`, `cache`, `web`, `nginx`,
  `celery_worker`, `celery_beat`. `web` should only go healthy *after* `db`+`cache`.
- **Redeploy** the stack → it returns to healthy with no manual step and no data loss (idempotent).
- ✅ Pass: healthy from a clean deploy with zero shell-in / manual migration.

### SC-004 — Static & media served through nginx (no unstyled site)
- Open `https://wger.ragnaforge.xyz` → the UI renders **fully styled**.
- `curl -sI https://wger.ragnaforge.xyz/static/<any-asset>` → **200** with a CSS/JS content-type.
- Upload an image in-app (e.g. an exercise/profile image), then `curl -sI` its `/media/…` URL → **200**.
- ✅ Pass: 0 broken/404 static or media assets; page is styled (not raw HTML).

### SC-006 — TLS + Homepage + login works behind the proxy
- `curl -sI http://wger.ragnaforge.xyz` → redirect to HTTPS; `https://` serves a **valid** cert.
- Homepage (`home.ragnaforge.xyz`) shows a **wger** tile in the Apps group linking to the UI.
- Log in and submit a form (e.g. add a workout) → succeeds with **no** "disallowed host" and **no** CSRF
  error; the address bar / links stay on `https://wger.ragnaforge.xyz`.
- ✅ Pass: valid TLS, tile present, 0 host/CSRF errors.

### SC-001 / SC-002 — Log data & it persists across device + redeploy
- As the operator, record a **workout**, a **body-weight** entry, and a **nutrition** item.
- Log out, log back in from **another** LAN/VPN device → all three present.
- **Redeploy** the stack (and/or restart containers) → account + all three entries intact, **zero loss**.
- ✅ Pass: data survives logout/login and a redeploy.

### SC-005 — Celery healthy + exercise DB populates (best-effort)
- `celery_worker` reports healthy (`celery -A wger inspect ping`); `celery_beat` is running.
- After the initial sync (needs outbound internet; may take a while), the **exercise database** is
  populated (browse exercises in-app).
- Confirm core logging (SC-001) works **even while** the sync is running / if it's unavailable.
- ✅ Pass: workers healthy; exercise library populates; logging never blocked by sync.

### SC-007 — Registration closed
- Log out and open the sign-up / register path → **refused** (no self-registration).
- ✅ Pass: an unauthenticated visitor cannot create an account.

### SC-008 — No public exposure (audit)
- `docker ps` on the Dell → **no** published host ports for any wger service (Traefik-only ingress;
  `db`/`cache` internal). Confirm **no** router port-forward exists for wger.
- From outside the LAN/VPN (e.g. cellular, no VPN), `wger.ragnaforge.xyz` does **not** resolve/serve.
- ✅ Pass: 0 public paths; LAN/Tailscale/VPN-only.

### SC-009 — No committed secrets + all state on the Dell (audit)
- `git grep` for the real `WGER_SECRET_KEY` / `WGER_POSTGRES_PASSWORD` values → **0** hits (only
  `${VAR}` refs and `.mise.toml.example` placeholders).
- `docker volume ls` on the Dell shows `wger-static`, `wger-media`, `wger-pgdata`, `wger-celerybeat`
  (+ optional `wger-redis`); **0** wger state on the Mac or under `/srv/nfs`.
- ✅ Pass: 0 secrets in git; 100% of state Dell-local.

## Optional plane-3 assert

Run `stacks/wger/configure/setup.yml` (idempotent, GET-only): asserts `/` 200, a `/static/…` asset 200
(nginx serving), and self-registration refused. A second run reports no changes. See
[contracts/wiring.md](./contracts/wiring.md).

## Done when

All of SC-001…SC-009 pass: a fresh wger instance logs and persists fitness data over valid TLS, comes up
healthy from a cold deploy with static/media served through nginx and no manual step, has registration
closed, is reachable only on LAN/VPN, and keeps 0 secrets in git with 100% of state on the Dell.
