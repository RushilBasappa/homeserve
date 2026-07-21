# Runbook — Phase 7a: Apps: Finance & Secrets (Actual + Vaultwarden + Sure)

The first **personal-data apps** — passwords (Vaultwarden), budgeting (Actual), and net-worth
(Sure). Three isolated, Dell-only, **LAN/VPN-only** stacks. This runbook is the bring-up order, the
**one-time data-preservation** steps, the security audits, and the SC-001…009 evidence table.

Spec/design: `specs/008-finance-secrets-apps/` (spec.md, plan.md, research.md, contracts/,
quickstart.md). Operating the fleet: [[homeserve-ops-access]].

---

## Prerequisites

- Phase-3 edge live (Traefik + wildcard TLS + AdGuard + Homepage); `*.ragnaforge.xyz` → the Dell.
- `.mise.toml` has real values for the three container secrets, and they are forwarded to Periphery:
  - `VAULTWARDEN_ADMIN_TOKEN` — `docker run --rm -it vaultwarden/server /vaultwarden hash` → paste the
    `$argon2id$…` string **verbatim** (single `$`, no escaping; see the stack header for why).
  - `SURE_SECRET_KEY_BASE` — `openssl rand -hex 64`.
  - `SURE_POSTGRES_PASSWORD` — `openssl rand -hex 32`.
  - Then `make sync-secrets` + recreate the Periphery container.
  - **Actual needs no secret** (login set in-app).

---

## Bring-up order

1. Declare the three stacks in `komodo/stacks.toml`, push, `RunSync` (or wait ≤5 min for the git poll).
2. **Vaultwarden** (MVP) — restore existing data first if preserving (below); deploy; unlock; confirm
   signups closed. Optionally run `stacks/vaultwarden/configure/setup.yml`.
3. **Actual** — restore existing data first if preserving (below); deploy; confirm the budget loads.
4. **Sure** — deploy the four-service stack **cold**; watch `db`+`redis` go healthy, then `web`
   self-migrate (`rails db:prepare`) and `/up` return 200; create the first account; then set
   `ONBOARDING_STATE=closed` and redeploy.
5. **Redeploy `homepage`** with the three new tiles.

---

## One-time data preservation (import existing vault + budget)

> This is a **one-time** migration step, not automated backup. Scheduled/offsite backups are **Phase 10**.

### Vaultwarden (existing vault)
1. Deploy the stack once (creates the empty `vaultwarden-data` volume), then **stop** the container.
2. Restore the pre-migration data folder into `vaultwarden-data` — at minimum `db.sqlite3` +
   `rsa_key.pem`/`rsa_key.pub.pem` + `attachments/` (add `sends/` + `config.json` for full continuity).
3. **Delete any stale `db.sqlite3-wal`** before starting (avoids WAL/DB mismatch corruption).
4. Start the container; unlock with the master password → existing logins present (SC-001).
- **No preserved data?** Deploy with `SIGNUPS_ALLOWED=true`, create the account(s) in the app, then set
  `SIGNUPS_ALLOWED=false` and redeploy.

### Actual (existing budget)
- **Volume restore (verbatim):** restore the whole `/data` (`server-files/` incl. `account.sqlite` +
  `user-files/`) into `actual-data`. Preserves users, sessions, and every budget.
- **or In-app `.zip`:** export a budget from the client, import into the fresh server via
  *Import → Actual* (encrypted budgets need their password).
- **No preserved data?** Create a new budget in-app.

---

## Security audits

- **No public exposure (SC-006):** `docker ps` shows **no** host port maps for these services; Sure's
  `db`/`redis` are reachable only on the internal `sure` network; **no** router port-forward targets any
  of the three. All reachable only on LAN/Tailscale/VPN.
- **No committed secrets (SC-007):** `git grep` the repo for the three secret values and `changeme-` →
  **0** real values; only `${VAR}` references + `.mise.toml.example` placeholders.
- **Vaultwarden lockdown (SC-002):** logged out, a browser **register** attempt is refused; `/admin`
  demands the Argon2 token.

---

## SC evidence table (fill from live runs)

| SC | What | Result | Date |
|----|------|--------|------|
| SC-001 | Vault preserved + unlock over TLS (0 loss) | | |
| SC-002 | Registration refused + /admin token-gated | | |
| SC-003 | Budget preserved + edit survives restart (0 loss) | | |
| SC-004 | Sure cold-deploy healthy (self-migrates) + data survives redeploy | | |
| SC-005 | All three over valid TLS + Homepage tiles | | |
| SC-006 | No public exposure (LAN/VPN only) | | |
| SC-007 | No committed secrets | | |
| SC-008 | Idempotent rebuild; all state on the Dell | | |
| SC-009 | Stack isolation — drop one, others live | | |

---

## Notes

- **Golden rule:** every volume (`vaultwarden-data`, `actual-data`, `sure-pgdata`, `sure-storage`,
  `sure-redis`) is on the **Dell**; nothing on the Mac or `/srv/nfs`.
- **Sure is the heaviest 7a component** and the natural retire-candidate if the Actual-vs-Sure trial
  favours Actual — the isolated stacks make that a clean one-stack removal (SC-009).
- **Pinned tags:** Vaultwarden `1.36.0-alpine`, Actual `26.7.0-alpine` (verify at each releases URL);
  **Sure** pins the rolling `stable@sha256:<digest>` (seerr-style) — record the digest here on deploy.
