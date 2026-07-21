# Quickstart — Validate Phase 7a (Finance & Secrets)

A runnable validation guide that proves the phase end-to-end, mapped to **SC-001…SC-009**. Not
implementation — see `tasks.md` (after `/speckit-tasks`) and the stack files for that. Who-connects-to-
whom is in `contracts/wiring.md`; the stack/port/secret table is in `contracts/stack-inventory.md`.

## Prerequisites

- Phase 3 edge up (Traefik + wildcard TLS + AdGuard + Homepage). No new edge work.
- Secrets present in `.mise.toml` and forwarded to Periphery (`VAULTWARDEN_ADMIN_TOKEN`,
  `SURE_SECRET_KEY_BASE`, `SURE_POSTGRES_PASSWORD`) — `make sync-secrets` + a Periphery recreate.
- Any pre-migration **vault** / **budget** export available if you intend to preserve existing data
  (Phase-1 preservation); otherwise the fresh-start paths apply.
- Operating the fleet: SSH/Komodo per [[homeserve-ops-access]].

## Bring-up order

1. Declare the three stacks in `komodo/stacks.toml`, push, `RunSync` (or wait ≤5 min).
2. **Vaultwarden** — (if preserving) stop/restore `/data` into `vaultwarden-data` first; deploy;
   unlock; confirm signups closed. Optionally run `stacks/vaultwarden/configure/setup.yml`.
3. **Actual** — (if preserving) restore `/data` into `actual-data` or import a `.zip` in-app; deploy;
   confirm the budget loads.
4. **Sure** — deploy the four-service stack; watch `db`/`redis` go healthy, then `web` self-migrate and
   `/up` return 200; create the first account, then set `ONBOARDING_STATE=closed` and redeploy.
5. **Redeploy `homepage`** with the three new tiles.

---

## Validation scenarios

### SC-001 — Vault preserved + unlock (Vaultwarden)
- Open `https://vaultwarden.ragnaforge.xyz`, unlock with the master password.
- **Expect**: the preserved logins are present with **0 loss** (or a clean empty vault if nothing was
  preserved). Served over **HTTPS with a valid cert**.

### SC-002 — Registration closed + admin gated
- Log out; attempt to **register a new account**.
- **Expect**: signup is **refused** (`SIGNUPS_ALLOWED=false`).
- Open `/admin` without the token.
- **Expect**: access denied until the Argon2 `ADMIN_TOKEN` is supplied.

### SC-003 — Budget preserved + edit survives restart (Actual)
- Open `https://actual.ragnaforge.xyz`; confirm the preserved budget loads (or create one). Edit/add an
  entry.
- `DestroyStack` + `DeployStack` (or redeploy) `actual`.
- **Expect**: the budget and the edit are **fully present** after restart — **0 loss** (`actual-data`
  on the Dell).

### SC-004 — Sure cold-deploy healthy + data survives redeploy
- From a **cold** deploy, watch the stack: `db` + `redis` reach healthy, then `web` runs `db:prepare`
  and `GET /up` returns 200 — **0 manual steps**.
- Open `https://sure.ragnaforge.xyz`, create an account and a financial account; note the net-worth view.
- Redeploy `sure`.
- **Expect**: the account and its data **persist** with **0 loss / 0 re-registration** (`sure-pgdata`).

### SC-005 — TLS front door + Homepage tiles
- Open each of `https://vaultwarden.ragnaforge.xyz`, `https://actual.ragnaforge.xyz`,
  `https://sure.ragnaforge.xyz`.
- **Expect**: all load over **HTTPS with a valid cert**; HTTP→HTTPS redirects.
- Open Homepage (`home.ragnaforge.xyz`).
- **Expect**: all three appear as **tiles** in the Apps group linking to their UIs.

### SC-006 — No public exposure (audit)
- Confirm **no** host `ports:` are published by any service (`docker ps` shows no port maps for these),
  Sure's `db`/`redis` are reachable only on the internal `sure` network, and **no** router port-forward
  targets them.
- **Expect**: all three reachable only on **LAN/Tailscale/VPN** — **0** public exposure (FR-015).

### SC-007 — No committed secrets (audit)
- `git grep` the repo for the three secret values and for `changeme-`.
- **Expect**: **0** real secret values in git; only `${VAR}` references and `.mise.toml.example`
  placeholders. Actual contributes no secret at all.

### SC-008 — Idempotent rebuild, all state on the Dell
- On a clean rebuild from the repo via Komodo, deploy all three; re-run the Vaultwarden assert and
  redeploy each once more.
- **Expect**: all three reach a **healthy** state; the re-run/redeploy **changes nothing** (idempotent);
  every volume is confirmed on the **Dell** and **0** state is on the Mac or `/srv/nfs`.

### SC-009 — Stack isolation (drop one, others live)
- Stop/remove **one** stack (simulating retiring the Actual-vs-Sure trial loser — e.g. `sure`).
- **Expect**: the other two remain **running and reachable** over TLS — the stacks are provably isolated
  (FR-014).

---

## Done when

All of SC-001…SC-009 pass and are recorded (evidence table) in
`docs/runbooks/phase7a-finance-secrets.md`; `PLAN.md` Phase 7a marked complete.
