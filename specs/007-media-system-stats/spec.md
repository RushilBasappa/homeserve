# Feature Specification: Phase 6 — Media & System Stats (Tautulli + Beszel)

**Feature Branch**: `007-media-system-stats`

**Created**: 2026-07-20

**Status**: Draft

**Input**: User description: "next phase"

## Context

Phase 5 stood up a working media pipeline (request → download → library → play on Jellyfin and Plex). Phase 6 makes that pipeline and the two small laptops it runs on **observable**: at a glance, the operator should see **who is watching what right now** and **whether the box can take it** — the audience and the load.

This phase adds two focused, low-footprint tools and nothing else:

1. **Tautulli — media watch stats (Plex).** Per-user history, now-playing sessions, per-stream bandwidth, and — the number that actually matters on a 2-core i3 — the **direct-play vs transcode** breakdown that tells the operator when Plex is cooking the iGPU/CPU. Tautulli talks to Plex **read-only** via the Plex server token; its SQLite history database lives on the Dell per the golden rule. Plex is the primary server for watch stats; the earlier Jellyfin-stats tool (Jellystat) was dropped as unused, so Jellyfin-specific watch analytics are intentionally not part of this phase.

2. **Beszel — host & container metrics (fleet).** A hub on the Dell plus a lightweight agent on the Mac give **one fleet view**: CPU, RAM, disk usage %, network, temperatures, and per-container stats, with configurable thresholds. Beszel was chosen over Netdata (heavier, cloud-nudgey) and Prometheus/Grafana (multi-GB, deferred) specifically to fit the ~7.5 GB nodes. Disk **health**/SMART (Scrutiny) is intentionally skipped for now — Beszel's usage % is enough.

This phase is **dashboards and visibility only**. It surfaces load thresholds and now-playing state, but it does **not** send any push notifications: turning Beszel threshold breaches and service-down events into phone pushes (via ntfy/Uptime Kuma) is deliberately deferred to Phase 9 (Alerting). Both new UIs are routed through the existing edge and appear on the Homepage front door so "see current streams + per-node load" is one page away.

All stateful config (Tautulli's history DB, Beszel's hub database) stays on the Dell per the golden rule; the Mac runs only the stateless Beszel agent.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See who is watching, and whether Plex is transcoding (Priority: P1) 🎯 MVP

As the operator, I open one page and immediately see the **current Plex streams** — who is watching what, on which device, at what bitrate — and crucially whether each stream is a cheap **direct play** or an expensive **transcode** that is loading the Dell's iGPU/CPU. Over time I can also look back at **per-user watch history** to inform (manual) cleanup decisions from Phase 5.

**Why this priority**: This is the "see the audience and the load it creates" half of the phase and the single most actionable signal on a 2-core box — a room full of transcodes is exactly what will make the i3 fall over, and the operator currently has no way to see it. It is independently valuable even if host metrics are never added: knowing what Plex is doing right now is the MVP.

**Independent Test**: With Plex connected and at least one title played, open the media-stats UI and confirm it shows now-playing sessions with per-stream direct-play/transcode status and bandwidth, and that per-user watch history accumulates across sessions and survives a container restart.

**Acceptance Scenarios**:

1. **Given** Plex is running and a member is streaming a title, **When** the operator opens the media-stats page, **Then** it shows that active session with the user, title, device, bitrate, and whether it is direct play or transcode.
2. **Given** several titles have been watched over time, **When** the operator opens the history view, **Then** it shows per-user watch history (what, when, how much) as input to manual deletion decisions.
3. **Given** the media-stats service is restarted or redeployed, **When** it comes back up, **Then** previously recorded history is still present (the history database persisted on the Dell), not reset.
4. **Given** the media-stats tool connects to Plex, **When** it reads sessions and history, **Then** it does so **read-only** via the Plex server token and never modifies the Plex library or the media files.

---

### User Story 2 - See per-node and per-container load across the fleet (Priority: P1)

As the operator, I open one hub and see **both** laptops at once — the Dell and the Mac — with each node's CPU, RAM, disk usage %, network, and temperature, plus **per-container** resource use, and a visible indicator when any metric crosses a configured threshold (e.g. disk over 85%). I do not have to SSH into each box and run `docker stats` by hand.

**Why this priority**: This is the "whether the box can take it" half of the phase. On two 7.5 GB laptops running the full stack, a disk filling up or a container eating RAM is a real and recurring failure mode; a single fleet view is what turns "something's wrong" into "the Dell's disk is at 90%." It is independently testable and valuable even without the media stats.

**Independent Test**: Deploy the hub on the Dell and the agent on the Mac, open the hub, and confirm both nodes report live CPU/RAM/disk %/network/temps and per-container stats; then confirm a configured threshold (e.g. disk %) shows a breach indicator when crossed, and that the Mac node degrades gracefully (shown as down, not an error) when the Mac is asleep or off.

**Acceptance Scenarios**:

1. **Given** the hub is on the Dell and an agent is on the Mac, **When** the operator opens the hub, **Then** both nodes appear with live CPU, RAM, disk usage %, network, and temperature readings.
2. **Given** containers are running on a node, **When** the operator views that node, **Then** per-container resource usage (CPU/RAM at minimum) is visible for that node's containers.
3. **Given** a threshold is configured (e.g. disk usage > 85%), **When** a metric crosses it, **Then** the hub visibly indicates the breach (no push notification is required in this phase).
4. **Given** the Mac is asleep, off, or otherwise unreachable, **When** the operator views the hub, **Then** the Mac node is shown as down/stale rather than breaking the view, and it reappears automatically when the Mac comes back.
5. **Given** the hub is restarted or redeployed, **When** it comes back up, **Then** recorded metric history persists (hub database on the Dell) rather than resetting.

---

### User Story 3 - One front door: both stats surfaces on Homepage with valid TLS (Priority: P2)

As the operator (and household), I reach both new tools the same way as every other app — at `https://<name>.ragnaforge.xyz` with a valid certificate — and I see them on the **Homepage** dashboard, ideally with a now-playing widget so the front door itself shows current streams and node load without opening either full UI.

**Why this priority**: Consistency and discoverability matter, but they ride on top of the two working data planes (US1, US2) and can be added after them. The core value is the data; the unified front door is polish that makes the data a glance away.

**Independent Test**: From a device on LAN/Tailscale, open `https://tautulli.ragnaforge.xyz` and `https://beszel.ragnaforge.xyz`, confirm both load with valid TLS, and confirm both appear as tiles on the Homepage dashboard (with a now-playing/stats widget where the tool supports it).

**Acceptance Scenarios**:

1. **Given** the edge (Traefik + wildcard cert) from Phase 3, **When** the operator opens each new tool's hostname, **Then** it loads over HTTPS with a valid certificate and HTTP is redirected to HTTPS.
2. **Given** the Homepage dashboard, **When** the operator opens it, **Then** both the media-stats and the fleet-metrics tools appear as tiles linking to their UIs.
3. **Given** the media-stats tool exposes a now-playing/summary widget, **When** it is wired into Homepage, **Then** the dashboard shows current stream count (and, where supported, node load) without opening the full UI.

---

### Edge Cases

- **Mac node asleep / off**: the Mac is a laptop that is frequently asleep or powered off; the fleet hub MUST treat a missing agent as "node down/stale," not as a hard error, and recover automatically when the Mac returns (US2 scenario 4).
- **Plex token rotation / re-auth**: if the Plex server token changes (re-login, server claim change), the media-stats tool's read-only connection must be re-establishable from the pinned credential/config without hand-clicking, and a stale token must surface as a visible "cannot reach Plex" state rather than silently showing empty stats.
- **Stats DB growth**: Tautulli's SQLite history and Beszel's metric history grow over time; retention/DB location must be bounded and on the Dell so they neither fill the small disk unexpectedly nor land on the shared NFS namespace.
- **No push in this phase**: a threshold breach or a stopped stream produces a **visible dashboard indicator only** — there is intentionally no phone push, email, or ntfy message (that wiring is Phase 9). This must be an explicit, documented boundary, not an oversight.
- **Container churn / redeploy**: redeploying the media or monitoring stacks (Komodo) must not reset accumulated history or drop the fleet agents' registration; persistence and agent trust must survive a normal redeploy.
- **Read-only guarantee**: the media-stats tool must never write to, delete from, or otherwise mutate the Plex library or the on-disk media — it is observational only, distinct from the Phase 5 deletion tool.
- **Resource pressure from the observers themselves**: the monitoring tools must be light enough that they do not themselves become the load problem on the 7.5 GB nodes (the reason Prometheus/Grafana and Netdata were rejected).
- **Jellyfin watch stats gap**: because Jellystat was dropped, Jellyfin-side watch analytics are absent; anyone watching only via Jellyfin will not appear in media stats. This is an accepted, documented limitation, not a bug.

## Requirements *(mandatory)*

### Functional Requirements

**Media watch stats (US1)**

- **FR-001**: The system MUST provide a media-stats service that shows **current Plex sessions** (now-playing) including, per stream, the user, title, device/player, bitrate/bandwidth, and whether the stream is **direct play** or **transcode**.
- **FR-002**: The media-stats service MUST record and display **per-user watch history** (title, timestamp, duration/percent watched) accumulated over time, usable as informational input to the Phase 5 manual-deletion decisions.
- **FR-003**: The media-stats service MUST connect to Plex **read-only** via the Plex server token and MUST NOT modify the Plex library, its metadata, or the on-disk media.
- **FR-004**: The media-stats service's history database MUST persist on the **Dell** (local named volume, not the shared NFS namespace) and MUST survive container restart/redeploy without data loss.
- **FR-005**: The media-stats service's history retention MUST be bounded/configurable so its database does not grow unbounded on the Dell's small disk.

**Fleet host & container metrics (US2)**

- **FR-006**: The system MUST provide a fleet-metrics **hub** on the Dell that displays, per node, live **CPU, RAM, disk usage %, network, and temperature**.
- **FR-007**: The fleet-metrics system MUST report metrics for **both** nodes — the Dell (local) and the Mac (via a lightweight agent) — in **one** view, without the operator SSHing into either box.
- **FR-008**: The fleet-metrics system MUST display **per-container** resource usage (CPU and RAM at minimum) for containers on each reporting node.
- **FR-009**: The fleet-metrics system MUST support **configurable thresholds** (e.g. disk usage > 85%, sustained high load) and MUST visibly indicate on the dashboard when a threshold is breached. (Sending that breach to a phone/push channel is out of scope — Phase 9.)
- **FR-010**: The fleet-metrics hub MUST tolerate an **unreachable agent** (e.g. the Mac asleep/off): the affected node is shown as down/stale rather than breaking the view, and it reappears automatically when the node returns.
- **FR-011**: The fleet-metrics hub's data (registered agents + metric history) MUST persist on the **Dell** and survive a normal container redeploy without re-registering agents by hand.

**Dashboards, edge & front door (US3)**

- **FR-012**: Every user-facing service in this phase MUST be reachable at `https://<name>.ragnaforge.xyz` with valid TLS via the existing edge (Traefik + wildcard cert), with HTTP redirected to HTTPS, consistent with Phase 3.
- **FR-013**: Both new tools MUST appear on the **Homepage** dashboard as tiles linking to their UIs; where a tool exposes a now-playing/summary widget, that widget SHOULD be wired into Homepage so current streams (and, where supported, node load) are visible from the front door.

**Scope boundary — dashboards only**

- **FR-014**: This phase MUST NOT send any push/alert notifications (no ntfy, email, SMS, or chat pushes) for threshold breaches, stream events, or service state; it provides **visible dashboard indicators only**. Notification wiring is deferred to Phase 9.
- **FR-015**: This phase MUST NOT introduce disk-health/SMART monitoring (Scrutiny), uptime/up-down probing (Uptime Kuma), or a heavyweight metrics stack (Prometheus/Grafana); the selected tools MUST stay within the lightweight footprint that fits the nodes.

**Platform & operational (cross-cutting)**

- **FR-016**: All application configuration/state for these tools (media-stats history DB, fleet-hub DB) MUST live on the **Dell** (local named volumes) and MUST NOT be placed on the shared `/srv/nfs` namespace. The Mac runs only the stateless fleet agent per the golden rule.
- **FR-017**: The stack MUST be deployable and reproducible from the repository via the existing **Komodo/Compose** workflow, with secrets (the Plex token, any hub/agent shared key) sourced from `mise` and never committed.
- **FR-018**: Inter-tool connections that make the stack functional — the media-stats→Plex read-only link and the fleet hub↔agent registration — MUST be established reproducibly from pinned configuration (no bespoke scripts), consistent with the Phase 5 three-plane discipline; any post-deploy application-plane wiring MUST be co-located with the stack it configures and be idempotent.
- **FR-019**: The two new tools' **total resource footprint** MUST fit within the Dell's remaining memory budget alongside the Phase 5 stack, or the plan MUST explicitly document which component runs where to stay within it.

### Key Entities *(include if feature involves data)*

- **Stream session**: a single active Plex playback — user, title, device/player, bandwidth, and its play method (direct play / direct stream / transcode); the unit the now-playing view is built from.
- **Watch-history record**: a completed/partial play event (user, title, timestamp, duration) accumulated in the media-stats history DB.
- **Node**: a fleet host (Dell or Mac) reporting CPU/RAM/disk %/network/temperature to the hub; may be present (agent reporting) or down/stale (agent unreachable).
- **Container metric**: per-container CPU/RAM (and where available network/IO) reported for a given node.
- **Threshold**: an operator-configured limit on a node metric (e.g. disk % > 85) whose breach is surfaced as a visible dashboard indicator (no push in this phase).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With a title playing on Plex, the operator can open **one** media-stats page and see the active session with its user, title, device, bandwidth, and a correct **direct-play vs transcode** indicator — within one refresh cycle and with zero SSH or manual queries.
- **SC-002**: The media-stats tool reads Plex **read-only**: over a full observation period it performs **0** writes/deletes to the Plex library or on-disk media (it never mutates media state).
- **SC-003**: Per-user watch history survives a container restart/redeploy with **0** loss of previously recorded events (history DB persisted on the Dell).
- **SC-004**: The fleet hub shows **both** nodes' CPU, RAM, disk %, network, and temperature plus per-container CPU/RAM in **one** view, with **0** SSH sessions required to read current load.
- **SC-005**: A configured threshold (e.g. disk > 85%) produces a **visible** breach indicator on the hub within one refresh cycle when crossed.
- **SC-006**: When the Mac is asleep/off, the hub shows it as down/stale (not an error/blank page) and it returns to reporting **automatically** within one update cycle of the Mac waking, with **0** manual re-registration.
- **SC-007**: **0** push/alert notifications are emitted by this phase — every signal is a dashboard indicator only (confirming the Phase 9 boundary).
- **SC-008**: 100% of this phase's user-facing services are reachable at `https://<name>.ragnaforge.xyz` with valid TLS and listed as tiles on the Homepage dashboard, and the front door shows a live now-playing/stats summary where the tool supports a widget.
- **SC-009**: On a clean rebuild from the repo via Komodo, both tools deploy with their Plex link and hub↔agent registration reproduced from pinned config with **0** manual UI wiring beyond one-time credential provisioning, and re-deploying changes nothing (idempotent).
- **SC-010**: The two new tools' combined steady-state memory footprint stays within the documented budget for the nodes (they do not themselves become the resource problem), verified against the fleet metrics they report.

## Assumptions

- **Plex is the primary stats surface; Jellyfin stats are out**: watch analytics are Plex-only via Tautulli (read-only, server token). Jellystat was dropped as unused in Phase 5, so Jellyfin-specific watch stats are intentionally not provided; watching solely via Jellyfin will not appear in media stats. This is an accepted, documented limitation.
- **Tool selection follows PLAN.md Phase 6**: media watch stats = **Tautulli**; host/container metrics = **Beszel** (hub on Dell + agent on Mac). Beszel was chosen over Netdata (heavier, cloud-nudgey) and Prometheus/Grafana (multi-GB) explicitly to fit the ~7.5 GB nodes; the plan MAY substitute an equivalently light tool only if it preserves the same footprint and one-fleet-view property.
- **Dashboards only — notifications deferred**: this phase surfaces thresholds and now-playing as **visible indicators**; converting them to phone pushes (ntfy) and adding up/down probing (Uptime Kuma) is Phase 9. No push channel is wired here.
- **SMART/disk health skipped**: Scrutiny is intentionally not included — Beszel's disk usage % is deemed sufficient for now; disk-health monitoring may be reconsidered later.
- **Mac is a best-effort reporter**: the Mac laptop is frequently asleep or off (its Komodo Periphery agent shows NotOk when asleep — see [[homeserve-ragnaforge-mac-node]]); the fleet view treats the Mac agent as best-effort, showing it down/stale when unreachable rather than erroring.
- **Storage & golden rule**: both tools' state (Tautulli SQLite history, Beszel hub DB) lives on the **Dell** as local named volumes, never on `/srv/nfs`; only the stateless Beszel agent runs on the Mac.
- **Edge & dashboard are ready**: Phase 3's Traefik + wildcard TLS + AdGuard + Homepage are available for routing and surfacing both tools; the Mac-hosted agent has no web UI to route, so the Traefik-can't-route-Mac-containers constraint ([[homeserve-traefik-mac-routing]]) does not apply here (only the Dell-hosted hub UI is fronted).
- **Plex from Phase 5 is available and claimed**: a working Plex server with a server token exists; the token is provided via `mise` and pinned so Tautulli's connection is reproducible on redeploy.
- **Reproducibility discipline carries over**: deployment via Komodo/Compose, secrets via `mise`, and the three-plane separation (machine / deployment / application) established in Phase 5 apply unchanged; any application-plane wiring for these tools is co-located with the stack and idempotent.
- **Consumers**: primarily the **operator** (reads stats and load to inform capacity and manual-deletion decisions); household members are incidental (their streams appear in the stats, they do not use these tools directly).

## Out of Scope

- **Push/alerting** — turning threshold breaches, service-down, or stream events into phone/ntfy/email pushes, and up/down probing (Uptime Kuma) — that is **Phase 9 (Alerting)**.
- **Disk health / SMART** monitoring (Scrutiny) — intentionally skipped this phase.
- **Heavyweight metrics stacks** (Prometheus + Grafana) — deferred as too heavy for the 7.5 GB nodes; may be reconsidered post-migration (Phase 13).
- **Jellyfin-specific watch analytics** (Jellystat or equivalent) — dropped as unused; Plex/Tautulli is the sole stats surface.
- **Log aggregation / APM / tracing** — not part of the "audience + load" goal of this phase.
- **Acting on the stats** — automatically deleting or reclaiming media based on watch counts/age remains explicitly out of scope (Phase 5 keeps deletion manual-only); stats here are informational input only.
- **Backups of the stats databases** — Phase 10; these DBs are observability data, not irreplaceable state.
