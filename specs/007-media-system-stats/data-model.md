# Phase 1 — Data Model: Media & System Stats

The entities this phase observes and stores. This is an **observability** feature — the "data
model" is the shape of what the two tools read and persist, not a schema we author. All stateful
records live in **Dell-local named volumes** (`tautulli-config`, `beszel-data`); nothing lands on
`/srv/nfs`.

---

## Media watch stats (Tautulli)

### Stream session (transient — now-playing)
A single active Plex playback, read live from Plex (read-only) and shown on the now-playing view.

| Field | Notes |
|---|---|
| user | Plex account watching the stream |
| title | media item being played (movie / episode) |
| device / player | client app + device |
| bandwidth / bitrate | per-stream throughput |
| **play method** | **direct play** / direct stream / **transcode** — the headline load signal (SC-001) |
| progress | position / percent |
| state | playing / paused / buffering |

- **Source**: Plex API, read-only via `PLEX_TOKEN`. Not persisted as-is (it is *current* state).
- **Validation / guarantee**: Tautulli issues **no** writes to Plex or media (FR-003, SC-002).

### Watch-history record (persisted)
A completed/partial play event accumulated in Tautulli's SQLite history DB.

| Field | Notes |
|---|---|
| user | who watched |
| title | what was watched |
| timestamp | when |
| duration / percent watched | how much |
| play method | direct play / transcode (as recorded) |

- **Storage**: `tautulli-config` (SQLite) on the Dell — **persists across restart/redeploy**
  (FR-004, SC-003).
- **Retention**: bounded/configurable window so the DB does not grow unbounded (FR-005).
- **Use**: informational input to Phase-5 **manual** deletion decisions — never an action
  trigger (spec Out of Scope).

---

## Fleet metrics (Beszel)

### Node (System)
A monitored host reporting to the hub. Declared in git (`stacks/beszel/config.yml`), not
hand-added.

| Field | Notes |
|---|---|
| name | `ragnaforge-dell` / `ragnaforge-mac` |
| host / port | `DELL_LAN_IP` (local) / `MAC_LAN_IP`, agent port (default 45876) |
| pinned key | hub public key (`BESZEL_KEY`) the agent trusts |
| status | **up** (agent reporting) / **down / stale** (agent unreachable — e.g. Mac asleep) |
| metrics | CPU, RAM, disk usage %, network, temperature (both nodes full — both are Debian Linux) |

- **State transition**: `up → down/stale` when the hub can't reach the agent; **auto-recovers**
  `down → up` when the agent returns, with **no** manual re-registration (FR-010, SC-006).
- **Storage**: registration + metric history in `beszel-data` (PocketBase/SQLite) on the Dell —
  **persists across redeploy** (FR-011).

### Container metric
Per-container resource use for containers on a reporting node.

| Field | Notes |
|---|---|
| node | which host it runs on |
| container | container name |
| cpu / memory | required minimum (network/IO where available) |

- **Source**: the node's agent via read-only `docker.sock`.

### Threshold
An operator-configured limit on a node metric whose breach is a **visible** indicator.

| Field | Notes |
|---|---|
| metric | e.g. disk usage %, CPU, memory |
| limit | e.g. disk > 85% |
| breach indication | **visible dashboard indicator only** — **no** push channel wired (FR-014, SC-007) |

- **Boundary**: thresholds are *defined and shown*; converting a breach to a phone push is
  **Phase 9**. Zero notification agents are configured in this phase.

### Pinned key (trust material)
The ed25519 identity binding hub ↔ agents.

| Field | Notes |
|---|---|
| public key | `BESZEL_KEY` — non-secret; consumed by every agent so it only accepts this hub |
| private identity | held by the hub; pinned so trust survives redeploy **and** a clean volume-wipe rebuild (R3, SC-009) |

---

## Persistence & placement summary

| Record | Tool | Store | Node | Persists redeploy? |
|---|---|---|---|---|
| Watch-history | Tautulli | `tautulli-config` (SQLite) | Dell | ✅ (SC-003) |
| Node / System + metric history | Beszel hub | `beszel-data` (PocketBase) | Dell | ✅ (SC-011/FR-011) |
| Stream session (now-playing) | Tautulli | transient (live from Plex) | — | n/a |
| Container metric | Beszel agent → hub | `beszel-data` | Dell (hub) | ✅ |
| Pinned key | Beszel | `beszel-data` + pinned var | Dell | ✅ |

**Golden rule**: every persisted record is on the **Dell**. The Mac agent holds **no** state.
