# Runbook — resume (Reactive Resume, self-hosted résumé builder)

A single **Dell-only**, **LAN/VPN-only** stack. Reactive Resume v5 is a Node (Hono + Vite) app backed
by Postgres, with an optional Redis-backed `/agent` AI workspace. This runbook is the bring-up order,
the **first-run signup lockdown**, and the correctness/security audits.

Upstream: <https://github.com/AmruthPillai/Reactive-Resume> · Operating the fleet: [[homeserve-ops-access]].

> This is an **added app** riding the existing platform (edge/DNS/TLS/Komodo), **not** a formal PLAN
> phase (cf. wger).

**Why so lean vs the old guides:** most self-host walkthroughs online are for **v4**, which bundled a
`browserless`/Chrome service for PDF export and a Minio/S3 store. **v5 needs neither** — printing is
in-app, and storage falls back to the **local filesystem** (`/app/data`) when no `S3_*` keys are set.
So this stack is just `app` + `postgres` + `redis`.

---

## Prerequisites

- Phase-3 edge live (Traefik + wildcard TLS + AdGuard + Homepage); `resume.ragnaforge.xyz` → the Dell
  (wildcard `*.ragnaforge.xyz` already resolves, so no new DNS record is needed).
- `.mise.toml` has real values for the three container secrets, forwarded to Periphery:
  - `RESUME_AUTH_SECRET` — `openssl rand -hex 32` (Better Auth signing).
  - `RESUME_POSTGRES_PASSWORD` — `openssl rand -hex 32` (postgres password **and** the app's
    `DATABASE_URL` — one value, referenced twice).
  - `RESUME_ENCRYPTION_SECRET` — `openssl rand -hex 32` (at-rest crypto for saved AI providers).
  - Then `make sync-secrets` + recreate the Periphery container (per [[homeserve-ops-access]]).
- `komodo/stacks.toml` has the `resume` `[[stack]]` (server `ragnaforge-dell`); `RunSync` applied.

**Verify at deploy** (image-tag discipline): confirm the pinned
`ghcr.io/amruthpillai/reactive-resume:<tag>` in `stacks/resume/compose.yaml` is a current release and
that the inline env keys still match that image's `.env.example`. At authoring time `v5.2.3` resolves to
the same digest as `:latest`. Releases: <https://github.com/AmruthPillai/Reactive-Resume/releases>.

---

## Bring-up order

1. Declare the stack in `komodo/stacks.toml`, push, `RunSync` (or wait ≤5 min for the git poll).
2. **Deploy `resume` (cold)** via Komodo (`DeployStack`). The order converges automatically with **no
   manual step**: `postgres` + `redis` healthy → `app` runs Prisma migrations on boot → serves on :3000.
   First boot takes longer (migrations); the `app` healthcheck has a 60s `start_period`.
3. **FIRST-RUN SIGNUP LOCKDOWN.** The stack ships with `FLAG_DISABLE_SIGNUPS: "false"` so you can create
   the **first account**. Go to **`https://resume.ragnaforge.xyz`**, register, and confirm you can build
   a résumé. Then edit `stacks/resume/compose.yaml` → set `FLAG_DISABLE_SIGNUPS: "true"`, push, and
   **redeploy** so registration is closed (same pattern as Vaultwarden's `SIGNUPS_ALLOWED` and Sure's
   `ONBOARDING_STATE`). Email/password auth stays on; social OAuth is off unless you fill the
   `*_CLIENT_ID/SECRET` env.

Optional integrations (all OFF by default, add to the `app` env if wanted): SMTP for password-reset/verify
emails; Google/GitHub/LinkedIn/custom OAuth sign-in; S3 storage (set `S3_*` and drop the `resume-data`
volume). None are required for a working single-user instance.

---

## Audits (the invariants)

- **No public exposure**: `docker ps` on the Dell shows **no** published host ports for `resume` /
  `resume-db` / `resume-redis`; postgres/redis are internal to the `resume` network; **no** router
  forward targets resume. From off-LAN/off-VPN, `resume.ragnaforge.xyz` does not serve.
- **TLS behind proxy**: Let's Encrypt wildcard cert; HTTP→HTTPS; `curl -sI https://resume.ragnaforge.xyz`
  → 200 (or a login redirect), no host/CSRF errors — `APP_URL` matches the external URL.
- **Signups closed after first account**: with `FLAG_DISABLE_SIGNUPS: "true"` redeployed, the register
  flow is refused.
- **No committed secrets**: `git grep` finds **0** real values of `RESUME_AUTH_SECRET` /
  `RESUME_POSTGRES_PASSWORD` / `RESUME_ENCRYPTION_SECRET` — only `${VAR}` refs and `.example` placeholders.
- **Golden rule**: `docker volume ls` shows `resume_resume-data`, `resume_resume-pgdata`,
  `resume_resume-redis` on the **Dell**; **0** resume state on the Mac or under `/srv/nfs`.

---

## Backups gap (Phase 10)

This runbook stands the app up only. `resume-pgdata` (accounts, résumé documents) and `resume-data`
(uploaded avatars/assets + cached exports) are the irreplaceable state and become **Phase-10 backup
candidates**. The stand-up → Phase-10 window is a known, documented gap.
