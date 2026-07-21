# Phase 1 — Data Model: Finance & Secrets

The entities this phase creates and persists. These are **off-the-shelf apps** — the "data model"
is the shape of what each app stores and where, not a schema we author. Every persisted record lives
in a **Dell-local named volume** (golden rule; FR-017); nothing lands on `/srv/nfs` or the Mac.

---

## Passwords (Vaultwarden)

### Password vault (persisted)
The end-to-end-encrypted credential store. The server holds **only ciphertext**; the master password
never reaches it and is not stored.

| Field / artifact | Notes |
|---|---|
| `db.sqlite3` | vault items, users, org/collection metadata — all item contents encrypted client-side |
| `attachments/`, `sends/` | encrypted file attachments / Send blobs |
| `rsa_key.pem` / `rsa_key.pub.pem` | JWT signing keys — preserve to keep existing login sessions valid |
| `config.json` | /admin-saved settings (SMTP, etc.) |

- **Storage**: `vaultwarden-data` → `/data` on the Dell — **persists across restart/redeploy** (FR-004,
  SC-001, edge: no reset to empty vault).
- **Preservation (FR-002)**: restore the `/data` folder from a pre-migration copy (stop first; drop a
  stale `db.sqlite3-wal`); DB auto-migrates forward. Fresh start if nothing preserved.
- **Guarantee**: zero-knowledge encryption → master-password loss is unrecoverable by design (spec
  edge case), which is why Phase-10 backups matter.

### Account / registration state (config)
| Field | Notes |
|---|---|
| `SIGNUPS_ALLOWED` | **false** after initial account(s) — no open registration (FR-003, SC-002) |
| `ADMIN_TOKEN` | Argon2 PHC hash gating `/admin` (from `mise`; `$$`-escaped in compose) |
| `INVITATIONS_ALLOWED` | default true — invite household members with signups closed |

---

## Budgeting (Actual)

### Budget (persisted)
The budgeting dataset — accounts, categories, transactions — plus server-level auth.

| Field / artifact | Notes |
|---|---|
| `server-files/account.sqlite` | server password, sessions, budget-file metadata |
| `user-files/` | the budget files (binary/optionally end-to-end-encrypted blobs) |

- **Storage**: `actual-data` → `/data` on the Dell — **survives restart/redeploy** (FR-007, SC-003).
- **Preservation (FR-006)**: restore the whole `/data` volume (verbatim), **or** in-app `.zip`
  export/import per budget. Fresh budget created in-app if nothing preserved.
- **Auth**: server login password set **in-app on first run** (stored in `account.sqlite`) — no
  container secret needed.

---

## Net-worth / wealth tracking (Sure)

### Financial account & net-worth snapshot (persisted)
Operator-tracked accounts and balances over time, aggregated into the net-worth view.

| Field | Notes |
|---|---|
| accounts | manually entered / imported financial accounts (cash, investment, etc.) |
| balances / valuations | per-account values over time → net-worth aggregation |
| user / onboarding | first account created in-app; `ONBOARDING_STATE=closed` after (signup lockdown) |

- **Storage**: PostgreSQL 16 on `sure-pgdata` → `/var/lib/postgresql/data` on the Dell — **persists
  across redeploy** with no re-registration (FR-011, SC-004). ActiveStorage uploads on `sure-storage`
  → `/rails/storage` (shared web+worker). Redis (`sure-redis` → `/data`) holds only Sidekiq queue
  state (optional to persist).
- **Schema lifecycle**: the `web` container runs `rails db:prepare` on boot — creates + migrates the
  DB automatically; no manual step (FR-010).

### Background job (transient)
| Field | Notes |
|---|---|
| queue | Sidekiq jobs on Redis (market-data sync, imports) — run by the `worker` service |

- Not durable state; the `worker` relies on `web` having prepared the schema.

---

## Cross-cutting entities

### App config volume
The per-app Dell-local named volume that holds each app's state and must survive redeploys.

| Volume | Mount | App | Persists redeploy? |
|---|---|---|---|
| `vaultwarden-data` | `/data` | Vaultwarden | ✅ (SC-001) |
| `actual-data` | `/data` | Actual | ✅ (SC-003) |
| `sure-pgdata` | `/var/lib/postgresql/data` | Sure (db) | ✅ (SC-004) |
| `sure-storage` | `/rails/storage` | Sure (web+worker) | ✅ |
| `sure-redis` | `/data` | Sure (redis) | optional (queue only) |

**Golden rule**: every volume is on the **Dell**; nothing on the Mac or `/srv/nfs` (FR-017, SC-008).

### Secret
An operator-provisioned credential from `mise`, injected at deploy, never committed (FR-016, SC-007).

| Secret | Consumer | Form |
|---|---|---|
| `VAULTWARDEN_ADMIN_TOKEN` | vaultwarden `ADMIN_TOKEN` | Argon2 PHC hash (`$$`-escaped in compose) |
| `SURE_SECRET_KEY_BASE` | sure web + worker | 64-hex random |
| `SURE_POSTGRES_PASSWORD` | sure db + web + worker | 32-hex random |
| *(Actual: none)* | — | login password set in-app on first run |

---

## Persistence & placement summary

| Record | App | Store | Node | Persists redeploy? |
|---|---|---|---|---|
| Password vault | Vaultwarden | `vaultwarden-data` (SQLite + keys) | Dell | ✅ (SC-001) |
| Budget | Actual | `actual-data` (SQLite + blobs) | Dell | ✅ (SC-003) |
| Financial accounts / net-worth | Sure | `sure-pgdata` (PostgreSQL) | Dell | ✅ (SC-004) |
| ActiveStorage uploads | Sure | `sure-storage` | Dell | ✅ |
| Sidekiq queue | Sure | `sure-redis` | Dell | optional |
