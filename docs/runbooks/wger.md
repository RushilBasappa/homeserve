# Runbook — wger (self-hosted fitness / workout / nutrition tracker)

A single **Dell-only**, **LAN/VPN-only** stack. wger is a Django app with a **mandatory nginx** and a
Celery worker/beat — the **heaviest single stack in the lab**. This runbook is the bring-up order, the
**first-run security step** (change the bootstrap admin password), the correctness/security audits, and
the SC-001…009 evidence table.

Spec/design: `specs/009-wger-fitness/` (spec.md, plan.md, research.md, contracts/, quickstart.md).
Operating the fleet: [[homeserve-ops-access]].

> This is an **added app** riding the existing platform (edge/DNS/TLS/storage/Komodo), **not** a formal
> PLAN phase.

---

## Prerequisites

- Phase-3 edge live (Traefik + wildcard TLS + AdGuard + Homepage); `wger.ragnaforge.xyz` → the Dell.
- `.mise.toml` has real values for the two container secrets, forwarded to Periphery:
  - `WGER_SECRET_KEY` — `openssl rand -hex 50` (Django `SECRET_KEY`).
  - `WGER_POSTGRES_PASSWORD` — `openssl rand -hex 32`.
  - Then `make sync-secrets` + recreate the Periphery container (per [[homeserve-ops-access]]).
  - No JWT keys — the mobile app / PowerSync offline sync is **out of scope**.
- `komodo/stacks.toml` has the `wger` `[[stack]]` (server `ragnaforge-dell`); `RunSync` applied.

**Verify at deploy** (image-tag + env discipline): confirm the pinned `wger/server:<tag>` in
`stacks/wger/compose.yaml` is a current release, and that the inline env keys still match that image's
`config/prod.env`. Upstream: <https://github.com/wger-project/docker> ·
<https://hub.docker.com/r/wger/server/tags>.

---

## Bring-up order

1. Declare the stack in `komodo/stacks.toml`, push, `RunSync` (or wait ≤5 min for the git poll).
2. **Deploy `wger` (cold)** via Komodo (`DeployStack`). The order converges automatically with **no
   manual step**: `db` + `cache` healthy → `web` migrates + collects static → `nginx` + `celery_worker`
   → `celery_beat`.
3. **FIRST-RUN SECURITY STEP — change the admin password.** wger auto-creates a bootstrap `admin`
   account on first boot (default **`admin` / `adminadmin`**). Log in and **change the password
   immediately** (Dashboard → user menu → change password, or Django admin). This is the primary account;
   registration is closed (`ALLOW_REGISTRATION=False`), so add household members from within wger, not
   via self-signup.
4. (Optional) Run the plane-3 assert: `cd stacks/wger/configure && mise exec -- ansible-playbook setup.yml`
   → asserts `/` 200 + a static asset 200 (nginx serving) + reports the registration-page status. A
   second run is a no-op.

### The inline-nginx-config footgun

`stacks/wger/compose.yaml` ships the nginx config **inline** (`configs: content:`) because Komodo's
git-clone deploy can't resolve a relative `./config` bind. If you ever edit that block, a plain redeploy
will **not** pick it up — you must **recreate** the container (`DestroyStack` then `DeployStack`). See
[[homeserve-inline-configs-need-recreate]].

---

## Audits (the invariants)

- **No public exposure (SC-008)**: `docker ps` on the Dell shows **no** published host ports for any
  wger service; `db`/`cache` are internal to the `wger` network; **no** router forward targets wger.
  From off-LAN/off-VPN, `wger.ragnaforge.xyz` does not serve.
- **Static served through nginx (SC-004)**: the UI renders **fully styled**;
  `curl -sI https://wger.ragnaforge.xyz/static/admin/css/base.css` → **200**; an uploaded image's
  `/media/…` URL → **200**. (A 404 here = nginx not serving / route pointed at web:8000 / broken volume
  share.)
- **No committed secrets (SC-009)**: `git grep` finds **0** real values of `WGER_SECRET_KEY` /
  `WGER_POSTGRES_PASSWORD` — only `${VAR}` references and `.mise.toml.example` placeholders.
- **Golden rule (SC-009)**: `docker volume ls` shows `wger-static`, `wger-media`, `wger-pgdata`,
  `wger-redis` on the **Dell**; **0** wger state on the Mac or under `/srv/nfs`.

---

## Backups gap (Phase 10)

This runbook stands the app up only. `wger-pgdata` (accounts, logs) and `wger-media` (uploads) are the
irreplaceable state and become **Phase-10 backup candidates**; scheduled/offsite backups and DB dumps
are not part of standing wger up. The stand-up → Phase-10 window is a known, documented gap.

---

## SC-001…009 evidence table

Fill from the live runs (tasks T012 / T014 / T015 / T016 / T018 / T019 / T020 / T022).

| SC | What it proves | Evidence | Pass? |
|----|----------------|----------|-------|
| SC-001 | Log workout/weight/nutrition; present after re-login on another device | _(pending live run)_ | ☐ |
| SC-002 | Account + entries survive restart + redeploy — 0 loss | _(pending)_ | ☐ |
| SC-003 | Cold deploy healthy, no manual step; redeploy idempotent | _(pending)_ | ☐ |
| SC-004 | Static + media served through nginx; UI styled; 0 broken assets | _(pending)_ | ☐ |
| SC-005 | Celery worker/beat healthy; exercise DB populates; logging never blocked | _(pending)_ | ☐ |
| SC-006 | Valid TLS (HTTP→HTTPS) + Homepage tile + login with 0 host/CSRF errors | _(pending)_ | ☐ |
| SC-007 | Self-registration refused | _(pending)_ | ☐ |
| SC-008 | 0 public paths; 0 host ports; LAN/Tailscale/VPN-only | _(pending)_ | ☐ |
| SC-009 | 0 secrets in git; 100% state on the Dell | _(pending)_ | ☐ |
