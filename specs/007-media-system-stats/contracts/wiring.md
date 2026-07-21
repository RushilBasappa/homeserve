# Contract: Wiring (plane-3 / declarative connections)

Who connects to whom, with which credential, and how it is reproduced from code. Every edge is
either **declarative** (git-tracked config imported at deploy) or a **co-located idempotent
plane-3 play** (`stacks/<app>/configure/setup.yml`, GET-then-POST). No manual UI wiring beyond
one-time credential provisioning (spec FR-018, SC-009). All connections here are **read/observe**
only — none mutate media, libraries, or push notifications.

## Edges

| # | From → To | Purpose | Credential | Reproduced by |
|---|---|---|---|---|
| 1 | **Tautulli → Plex** | read now-playing + history (read-only) | `PLEX_TOKEN` (reused) | seeded `config.ini` (PMS host/port/token) **or** plane-3 API register; assert-play verifies |
| 2 | **Beszel hub → Dell agent** | poll host + container metrics | pinned hub key (`BESZEL_KEY`) | declarative `stacks/beszel/config.yml` system entry |
| 3 | **Beszel hub → Mac agent** | poll host + container metrics (best-effort) | pinned hub key (`BESZEL_KEY`) | declarative `stacks/beszel/config.yml` system entry (`MAC_LAN_IP:45876`) |
| 4 | **Homepage → Tautulli** | now-playing widget on the front door | `TAUTULLI_API_KEY` (deterministic) | inline `stacks/homepage/compose.yaml` widget + `{{HOMEPAGE_VAR_TAUTULLI_KEY}}` env |
| 5 | **Homepage → Beszel** | linked tile (no native widget) | none | inline `stacks/homepage/compose.yaml` tile |

## Edge 1 — Tautulli → Plex (read-only)

- **Internal URL**: `http://plex:32400` over the shared `traefik` network (container-to-container).
- **Auth**: `PLEX_TOKEN` (the existing Plex **server** token, already consumed by Maintainerr).
  Read-only monitoring — Tautulli issues **no** library/media writes (FR-003, SC-002).
- **Reproduction**:
  - *Primary* — seed `config.ini` before first start: PMS host/port, `PLEX_TOKEN`, PMS identifier,
    a **deterministic** `TAUTULLI_API_KEY`, `first_run_complete = 1` → the wizard is skipped.
  - *Verify* — `stacks/tautulli/configure/setup.yml` (idempotent): assert the Tautulli API is
    reachable, Plex is connected, and history is accumulating; **fail loudly** on a stale/broken
    token (surfacing the spec's "cannot reach Plex" edge case), never silently show empty stats.
  - *Fallback* — if seeding fights Tautulli's rewrites, the same play registers the Plex server
    via the Tautulli HTTP API (GET-then-POST). Re-runs are no-ops.

## Edges 2 & 3 — Beszel hub → agents (pinned key, declarative systems)

- **Trust**: every agent runs with `KEY=<BESZEL_KEY>` (hub public key) so it accepts **only** this
  hub. The hub's identity is **pinned** so trust survives redeploy and a clean volume-wipe rebuild
  (research R3).
- **Systems**: declared in git — `stacks/beszel/config.yml` lists the Dell and Mac systems (name,
  host, port 45876, key), imported by the hub on deploy → **no** manual "Add System" (FR-011).
  Shipped inline via Compose `configs:` (Komodo-safe, like Homepage).
- **Graceful down**: the hub **polls** each agent; an unreachable agent (Mac asleep/off) renders
  **down/stale** and **auto-recovers** on return — no re-registration (FR-010, SC-006).
- **Fallback**: if `config.yml` import is unreliable on the pinned version, a co-located
  `stacks/beszel/configure/setup.yml` registers the two systems via the PocketBase API
  (idempotent GET-then-POST); a failure is a visible play error.

## Edge 4 — Homepage → Tautulli widget

- Homepage's **native `tautulli` widget** (URL `https://tautulli.ragnaforge.xyz` or internal
  `http://tautulli:8181`, key = `TAUTULLI_API_KEY`) shows current stream count / now-playing on
  the front door (SC-008). The key is injected via a `{{HOMEPAGE_VAR_TAUTULLI_KEY}}` env
  substitution, so it is **not** hard-committed — `HOMEPAGE_VAR_TAUTULLI_KEY: ${TAUTULLI_API_KEY}`
  is added to the homepage service env (and forwarded to Periphery).

## Edge 5 — Homepage → Beszel tile

- A linked **Infrastructure** tile to `https://beszel.ragnaforge.xyz`. Homepage has **no native
  Beszel widget**; a `customapi` summary widget is an optional later add (not required — SC-008
  asks for a widget only "where the tool supports it").

## The no-push invariant (enforced here)

- **No edge in this contract carries a notification.** Beszel thresholds are defined (visible
  indicators) with **no** notification channel wired; Tautulli runs with **no** notification
  agents. Result: **0** pushes emitted (FR-014, SC-007). Phase 9 adds the ntfy channel on top of
  the thresholds defined here — it does not exist yet.

## Idempotency guarantee

Re-running any plane-3 play, re-importing `config.yml`, or redeploying any stack **changes
nothing** (GET-then-POST; declarative import is convergent). Verified by SC-009.
