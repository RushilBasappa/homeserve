# Quickstart — Validate Phase 6 (Media & System Stats)

A runnable validation guide that proves the phase end-to-end, mapped to **SC-001…SC-010**. Not
implementation — see `tasks.md` (after `/speckit-tasks`) and the stack files for that. Details of
who-connects-to-whom are in `contracts/wiring.md`; the stack/port/secret table is in
`contracts/stack-inventory.md`.

## Prerequisites

- Phase 3 edge up (Traefik + wildcard TLS + AdGuard + Homepage) and Phase 5 media stack deployed
  (Plex claimed, a title or two watched).
- Secrets present in `.mise.toml` and forwarded to Periphery (`PLEX_TOKEN`, `TAUTULLI_API_KEY`,
  `BESZEL_KEY`, `BESZEL_ADMIN_*`) — `make sync-secrets` + Periphery recreate.
- Operating the fleet: SSH/Komodo per [[homeserve-ops-access]].

## Bring-up order

1. Declare the four stacks in `komodo/stacks.toml`, push, `RunSync` (or wait ≤5 min).
2. **Deploy `tautulli`** (Dell) → run `stacks/tautulli/configure/setup.yml` (assert Plex link).
3. **Deploy `beszel`** (hub only) → then **`beszel-agent-dell`** (generic agent) → hub imports `config.yml` systems.
4. **Deploy `beszel-agent-mac`** (same generic file, node awake) → the Mac system goes green in the hub.
5. **Redeploy `homepage`** with the new tiles + Tautulli widget.

---

## Validation scenarios

### SC-001 — Now-playing + transcode indicator
- Play a title on Plex on a client that forces a **transcode** (e.g. change quality), and a second
  that **direct-plays**.
- Open `https://tautulli.ragnaforge.xyz`.
- **Expect**: both active sessions with user, title, device, bandwidth, and a **correct
  direct-play vs transcode** label — within one refresh, zero SSH/manual queries.

### SC-002 — Read-only Plex (0 writes)
- Over an observation window with Tautulli running, confirm **no** change to the Plex library,
  metadata, or on-disk media attributable to Tautulli (it monitors, it does not act).
- **Expect**: **0** writes/deletes to Plex or media (FR-003).

### SC-003 — History survives redeploy
- Note current per-user history counts. `DestroyStack` + `DeployStack` (or redeploy) `tautulli`.
- **Expect**: after it comes back, previously recorded history is **fully present** — `0` loss
  (SQLite DB in `tautulli-config` on the Dell).

### SC-004 — Both nodes, one view (+ per-container)
- Open `https://beszel.ragnaforge.xyz`.
- **Expect**: **both** `ragnaforge-dell` and `ragnaforge-mac` (Mac awake) with live CPU, RAM, disk
  %, network, temperature, **and** per-container CPU/RAM — in one view, `0` SSH sessions.
- *(Note — research R2)*: `ragnaforge-mac` runs Debian Linux, so the Mac agent reports full host
  metrics (CPU/RAM/disk %/net/temps) + per-container stats, just like the Dell — no macOS/VM caveat.

### SC-005 — Threshold indicator
- Configure a threshold you can cross (e.g. disk > a value just under current, or drive usage up).
- **Expect**: a **visible** breach indicator on the hub within one refresh — **no** push (SC-007).

### SC-006 — Mac asleep → graceful down → auto-recover
- Let the Mac sleep / power off.
- **Expect**: the Mac system shows **down/stale**, the view does **not** break/error, the Dell
  keeps reporting.
- Wake the Mac.
- **Expect**: the Mac returns to reporting **automatically** within one update cycle — `0` manual
  re-registration (FR-010).

### SC-007 — No push (boundary audit)
- Inspect Beszel + Tautulli notification config.
- **Expect**: **0** notification channels/agents configured; **0** pushes emitted by this phase —
  every signal is a dashboard indicator only (FR-014; confirms the Phase-9 line).

### SC-008 — TLS front door + Homepage
- Open `https://tautulli.ragnaforge.xyz` and `https://beszel.ragnaforge.xyz`.
- **Expect**: both load over **HTTPS with a valid cert**, HTTP→HTTPS redirects.
- Open Homepage (`home.ragnaforge.xyz`).
- **Expect**: both appear as **tiles**; the **Tautulli widget** shows a live now-playing/stream
  summary on the front door.

### SC-009 — Idempotent rebuild
- Re-run `stacks/tautulli/configure/setup.yml` and re-import Beszel `config.yml`; redeploy each
  stack once more.
- **Expect**: the Plex link and hub↔agent systems are reproduced from **pinned config** with `0`
  manual UI wiring beyond the one-time credentials; the re-run/redeploy **changes nothing**.

### SC-010 — Observers are not the load
- Read the tools' **own** steady-state memory from the Beszel per-container view.
- **Expect**: Tautulli + Beszel hub + agents combined stay within the documented budget (a few
  hundred MB) — they do not themselves become the resource problem (FR-019).

---

## Done when

All of SC-001…SC-010 pass and are recorded (evidence table) in `docs/runbooks/phase6-stats.md`;
`PLAN.md` Phase 6 marked complete.
