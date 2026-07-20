# Feature Specification: Phase 5 — Media Stack (ARR + Jellyfin/Plex)

**Feature Branch**: `006-media-stack`

**Created**: 2026-07-20

**Status**: Draft

**Input**: User description: "start with phase 5. the arr stack research to be modern and latest tech stack. and figure out a mechanism to delete media content also better like deleting should be across plex, radarr, sonarr, qbit etc. And anything that you recommend to add, let me know."

## Context

Phase 5 turns the storage namespace verified in Phase 4 (`/srv/nfs/media`, `/srv/nfs/downloads`) into a working, self-service media pipeline: household members request a movie or show, it is acquired automatically over a privacy-protected connection, imported into a clean library, and made playable on their devices — including the Fire TV that Phase 7 will onboard.

Two things shape this phase beyond the original PLAN.md sketch:

1. **Dual media servers, one library.** The operator has chosen to run **both Jellyfin and Plex** against the same on-disk library — Jellyfin for its free/open, no-account nature, Plex for its best-in-class TV/Fire TV client apps and remote streaming. Both read the same files; neither owns them.

2. **A real deletion mechanism — off-the-shelf, no scripts.** Today, removing a title means touching several apps by hand (the media server, Radarr/Sonarr, the download client, the request app) and it is easy to leave orphans — a stuck torrent still seeding, a file the library still lists, an unmonitored-but-not-deleted entry that silently re-downloads. The operator wants a **single deliberate action that cleanly removes a title everywhere at once**, with no automated/surprise deletions — and the mechanism must be a **maintained off-the-shelf application, not custom scripts or glue**. A dedicated cross-service deletion tool exists that natively covers exactly this: it is the only mature cleanup tool that spans **both Plex and Jellyfin** simultaneously and cascades a deletion to disk, Radarr/Sonarr (files + unmonitor), the download client (stop/remove the seeding torrent), and the Seerr request app — while supporting **manual, per-title** removal (not just automated rules), which is what makes the operator's manual-only posture work.

The phase also adopts the current (2026) generation of supporting tools so the stack is "modern and latest," not a five-year-old copy-paste: unified queue cleanup, code-driven quality profiles, missing-content hunting, a resilient indexer proxy, and watch statistics.

All stateful config stays on the Dell per the golden rule; the download client's egress is forced through a commercial VPN with a killswitch so the home IP is never exposed by torrent traffic.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Request → acquire (privately) → library → play (Priority: P1) 🎯 MVP

As a household member, I open one request page, search for a movie or show, and request it. Without any further manual steps, it is found, downloaded over a connection that never exposes our home IP, sorted into the right library folder, and becomes playable on my device (phone, laptop, or TV) in good quality.

**Why this priority**: This is the entire point of the media stack. If a request cannot become a playable file, nothing else in the phase matters. It is the minimum viable slice: a single working request-to-play path delivers the core value even before deletion, dual servers, or automation are added.

**Independent Test**: From a clean install, connect an indexer, request one title in the request app, and confirm it downloads through the VPN-guarded client, imports into `/srv/nfs/media`, appears in the media server, and plays back — while a leak check confirms the download traffic used the VPN egress, not the home IP.

**Acceptance Scenarios**:

1. **Given** an empty library and a configured indexer, **When** a member requests a specific movie, **Then** it is downloaded, imported to the movies library, and shows as available in the request app without manual file handling.
2. **Given** a title is in the library, **When** a member opens the media server on their device and presses play, **Then** it streams at watchable quality (direct play or transcode) without buffering stalls under normal home-network conditions.
3. **Given** the download client is running, **When** the VPN egress connection drops, **Then** the download client sends **no** traffic over the home internet connection (verifiable killswitch), and downloading resumes automatically when the VPN reconnects.
4. **Given** a completed download in the working area, **When** it is imported, **Then** the library copy and the download copy share storage (hardlink) so importing does not double disk usage, and seeding can continue.

---

### User Story 2 - One-action cascade delete across every service (Priority: P1)

As the operator, when I decide a title should go, I trigger **one** deletion action and the title is removed cleanly and completely — its files deleted from disk, its download stopped and removed from the torrent client (no lingering seed), its entry unmonitored so it will never silently re-download, it disappears from **both** media servers' libraries, and its request is cleared so it can be requested fresh later. No orphans, no manual visits to four apps, and nothing deleted that I did not explicitly choose.

**Why this priority**: This is the headline capability the operator explicitly asked for and the main gap in a stock arr stack. Manual multi-app deletion is the current pain; leftover orphans (seeding torrents, ghost library entries, auto-re-downloading monitors) are the current failure mode. It is P1 alongside the pipeline because "get media in" and "get media out cleanly" are the two halves of a usable library.

**Independent Test**: Take a title that exists in the library, is seeding in the download client, is monitored in Radarr/Sonarr, is visible in both media servers, and shows as available in the request app. Perform the single delete action. Then verify, across all six surfaces, that it is gone: file absent from disk, torrent removed from the client, entry unmonitored/removed in the arr app, absent from Jellyfin, absent from Plex, and re-requestable in the request app.

**Acceptance Scenarios**:

1. **Given** a title present across disk, download client, arr app, both media servers, and the request app, **When** the operator triggers the single delete action for that title, **Then** within one refresh cycle it is absent from every one of those surfaces.
2. **Given** the title was actively seeding, **When** it is deleted, **Then** the torrent is stopped and removed and its download-area data is removed, leaving no orphaned seed consuming upload/disk.
3. **Given** the title was monitored, **When** it is deleted, **Then** it is unmonitored (or removed) such that the automation does **not** re-download it on the next search cycle.
4. **Given** deletion is manual-only by design, **When** no operator action is taken, **Then** no title is ever deleted automatically by watch-state, age, or disk pressure.
5. **Given** a title spans multiple files (a TV series or season), **When** the operator chooses to delete at series or season granularity, **Then** exactly the chosen scope is removed and unrelated seasons/episodes are untouched.

---

### User Story 3 - A self-maintaining, high-quality library (Priority: P2)

As the operator, I want the stack to keep itself clean and complete without me babysitting it: quality profiles and release-filtering rules come from a maintained community standard and are applied from code (not clicked in by hand), stuck/blocked/malware-flagged downloads are detected and cleared and re-searched automatically, missing items and quality upgrades are hunted continuously, and flaky indexers behind bot-protection still work.

**Why this priority**: Turns a stack that "works once" into one that "keeps working." Not required for the first request-to-play, so it sits below the pipeline and deletion — but it is what makes the difference between the modern 2026 setup the operator asked for and a stock stack that silently rots (junk releases, wedged queues, dead indexers, permanently-missing items).

**Independent Test**: Introduce a deliberately stalled/blocked download and confirm it is automatically removed, blocklisted, and re-searched. Confirm quality profiles in the arr apps match the community standard and were applied from the repo, not hand-entered. Confirm a missing monitored item gets searched without manual intervention.

**Acceptance Scenarios**:

1. **Given** quality profiles and custom formats are defined in code, **When** the stack is (re)deployed, **Then** Radarr and Sonarr reflect those profiles without manual UI configuration, and re-running the sync is idempotent.
2. **Given** a download that is stalled, stuck, or flagged as unwanted/malware, **When** the cleanup tool runs, **Then** the download is removed, the release is blocklisted, and a fresh search is triggered — without operator action.
3. **Given** a monitored item is missing or below its quality cutoff, **When** the hunting tool runs, **Then** a search is triggered for it on a recurring basis until it is satisfied.
4. **Given** an indexer sits behind bot/anti-scraping protection, **When** the stack queries it, **Then** requests are proxied through the protection-solving service so results are still returned.

---

### User Story 4 - Both media servers and a single front door for requests + stats (Priority: P2)

As a household, we can watch on whatever app suits our device — Jellyfin (free, any device) or Plex (polished Fire TV / smart-TV / remote apps) — both showing the same library from the same files. We request through **one** page regardless of which player we use, and the operator can see basic watch statistics to inform (manual) cleanup decisions.

**Why this priority**: Client compatibility across the household and the Phase 7 Fire TV goal is real value, but it rides on top of a working pipeline and can be added after US1. Stats support the deletion decisions from US2 but are informational, not blocking.

**Independent Test**: Confirm the same title is playable from both Jellyfin and Plex against the same file with no duplicate storage, that a single request app drives acquisition regardless of player, and that watch statistics are visible for at least one played title.

**Acceptance Scenarios**:

1. **Given** one library on disk, **When** it is viewed in Jellyfin and in Plex, **Then** both list the same titles reading the same files, with no second copy of the media on disk.
2. **Given** a member uses either player, **When** they request a title, **Then** the request flows through the single request app and acquisition proceeds identically.
3. **Given** titles have been watched, **When** the operator opens the stats view, **Then** it shows what was watched and how much, usable as input to a manual deletion decision.

---

### Edge Cases

- **VPN down at play time / download time**: playback (LAN) is unaffected; downloads pause with zero home-IP leakage and resume on reconnect (US1 scenario 3).
- **Proton forwarded-port rotation / VPN restart**: when Proton rotates the forwarded port or the VPN gateway container restarts, the download client's listen port must re-sync automatically (FR-003a) so connectivity is not silently lost with a stale port; a stale/closed port must be detectable (client reports "not connectable").
- **Hardlink broken (import lands on a different filesystem)**: import must stay inside the single Phase-4 filesystem tree so it remains a hardlink/atomic move, never a slow cross-device copy that doubles disk; a misconfiguration here must be detectable.
- **Delete while seeding / delete mid-download**: the cascade delete must handle a title that is still downloading or actively seeding, not only a fully-imported one.
- **Partial delete failure**: if the single delete action removes the title from some surfaces but one service is unreachable, the operator must be able to see that it was incomplete and safely re-run it (idempotent), rather than being left with a hidden orphan.
- **Re-request after delete**: a deleted title, when requested again later, is treated as new and re-acquired cleanly (no stale "already available" state).
- **Duplicate/upgrade churn**: an automatic quality upgrade replaces the old file without leaving both copies or breaking the seeding torrent.
- **Two servers double-scanning**: Jellyfin and Plex scanning the same tree must not corrupt or lock files for each other; deletion must clear the title from both, not just whichever scanned first.
- **Small-node resource pressure**: the full tool set (two media servers + arr apps + cleanup/hunt/stats helpers) must fit the Dell's memory budget or explicitly place stateless helpers on the Mac per the golden rule.
- **First-boot ordering / unknown API keys**: if apps generate random API keys on first boot, dependent apps cannot be pre-wired declaratively; keys and endpoints must be fixed at deploy time (FR-024) so start-order races do not leave the stack half-connected.
- **Wiring step ordering / re-run**: the application-plane wiring step must run only after the stack is deployed and the apps are healthy with keys pinned; re-running it against an already-wired stack must be a no-op (idempotent), and a clean rebuild must reproduce every connection without manual clicks.
- **API payload drift on app upgrade**: because the application-plane wiring hand-encodes app API request bodies, a major app-version bump may change a field and break a connection — this must surface as a visible failure, not a silently unwired stack.
- **Indexer or tracker unavailable**: a missing/failing indexer degrades gracefully (other indexers still serve) rather than wedging the whole pipeline.

## Requirements *(mandatory)*

### Functional Requirements

**Acquisition pipeline (US1)**

- **FR-001**: Household members MUST be able to request a movie or TV title from a single request interface, without needing access to the underlying automation apps.
- **FR-002**: The system MUST automatically search configured indexers, select a release per the active quality rules, download it, and import it into the correct library location (`/srv/nfs/media/movies` or `/srv/nfs/media/tv`) with no manual file handling.
- **FR-003**: All download-client egress traffic MUST be forced through the Proton VPN tunnel (WireGuard), and the client MUST be prevented from transmitting over the home internet connection whenever the VPN tunnel is down (killswitch). No torrent traffic may reveal the home public IP.
- **FR-003a**: The download client MUST obtain an inbound (forwarded) port via Proton VPN's port forwarding so peers can connect (healthy connectivity/seeding ratio). Because Proton rotates the forwarded port, the download client's listen port MUST update to match the current forwarded port **automatically**, using maintained off-the-shelf tooling (a helper container image or the VPN gateway's built-in port-forwarding command) — **not** a hand-maintained cron/bash script, consistent with the operator's no-scripts constraint.
- **FR-004**: Importing MUST preserve the single-filesystem hardlink model from the Phase 4 contract — the download working area and the media library stay on one filesystem so import is a hardlink/atomic rename, never a cross-device copy, allowing continued seeding without duplicate disk usage.
- **FR-005**: Imported media MUST be playable through the media server(s) on common household devices at watchable quality, using hardware-accelerated transcoding where available.

**Cascade deletion (US2)**

- **FR-006**: The operator MUST be able to remove a title from the entire stack with a **single deliberate action**, at a sensible granularity (whole movie; whole series or a single season for TV).
- **FR-007**: The single delete action MUST result in: (a) the media files deleted from disk; (b) the associated download stopped and removed from the torrent client with its download-area data cleaned up (no orphan seed); (c) the title unmonitored or removed in Radarr/Sonarr so automation will not re-acquire it; (d) the title removed from **both** Jellyfin and Plex libraries; and (e) the corresponding request cleared in the request app so the title can be requested again fresh.
- **FR-008**: The system MUST NOT delete any media automatically — no deletions triggered by watch-state, age, ratings, duplicates, or disk pressure. Every deletion originates from an explicit operator action. (Automated reclamation is explicitly out of scope for this phase; see Out of Scope.)
- **FR-009**: The delete action MUST be safe to re-run (idempotent): re-issuing it for an already-partially-deleted title completes the removal on any surface that was missed, rather than erroring or creating inconsistency.
- **FR-010**: The operator MUST be able to confirm a deletion was complete — i.e., verify the title is absent from all of disk, download client, arr app, both media servers, and the request app.
- **FR-010a**: The cascade deletion MUST be performed by a maintained, off-the-shelf application that natively integrates with the media servers, Radarr/Sonarr, the download client, and the request app — **not** by custom scripts, hooks, or bespoke glue code. The chosen tool MUST cover **both** Plex and Jellyfin (whether via one multi-server instance or one instance per server, decided in planning) and MUST support **manual, per-title** removal so the manual-only posture (FR-008) is achievable without configuring automated age/watch/disk rules.

**Library quality & self-maintenance (US3)**

- **FR-011**: Quality profiles and release-filtering/custom-format rules MUST be defined in the repository (code) and applied to Radarr/Sonarr reproducibly and idempotently, sourced from a maintained community quality standard rather than hand-entered.
- **FR-012**: The system MUST automatically detect and remove stalled, stuck, blocked, or unwanted/malware-flagged downloads, blocklist the offending release, and trigger a fresh search — without operator intervention.
- **FR-013**: The system MUST continuously hunt for missing monitored items and eligible quality upgrades and trigger searches for them on a recurring schedule.
- **FR-014**: The system MUST be able to retrieve results from indexers protected by bot/anti-scraping challenges by routing those requests through a challenge-solving proxy.

**Dual servers, requests & stats (US4)**

- **FR-015**: Both Jellyfin and Plex MUST serve the **same** on-disk library from the **same** files, with no duplicate copy of the media created for the second server.
- **FR-016**: A single request app MUST drive acquisition for household members regardless of which player they use.
- **FR-017**: The operator MUST have access to watch statistics for the library, usable as informational input to manual deletion decisions.

**Platform & operational (cross-cutting)**

- **FR-018**: All application configuration/state MUST live on the Dell (local named volumes), and all shared media MUST live under the Phase 4 `/srv/nfs` tree; no app config may be placed on the shared namespace. Stateless helper services MAY run on the Mac per the golden rule.
- **FR-019**: Every user-facing service in the stack MUST be reachable at `https://<name>.ragnaforge.xyz` with valid TLS via the existing edge (Traefik + wildcard cert) and appear on the Homepage dashboard, consistent with Phases 3.
- **FR-020**: All media containers MUST run as `PUID=1000`/`PGID=1000` so files remain mutually readable/writable across services and both nodes, per the Phase 4 contract.
- **FR-021**: The stack MUST be deployable and reproducible from the repository via the existing Komodo/Compose workflow, with secrets (VPN credentials, indexer/API keys) sourced from `mise`, never committed.
- **FR-023**: The inter-app connections that make the stack functional — indexers→Radarr/Sonarr, download client→Radarr/Sonarr, subtitle provider→Radarr/Sonarr, request app→Radarr/Sonarr, and media-server/deletion-tool links — MUST be established from code with **no manual UI clicks and no bespoke scripts**, using: first-party native sync (Prowlarr application sync propagates indexers automatically), maintained config-as-code tools for quality profiles, deterministic pre-set credentials (each app's API key fixed from `mise`-provided values), and an idempotent post-deploy application-plane step for connections native sync does not cover. Stale third-party tools (e.g. Buildarr) MUST NOT be used. The wiring MUST be re-runnable and idempotent so a clean rebuild reproduces every connection.
- **FR-023a**: The three configuration planes MUST remain separated: machine-plane provisioning (`provision/`) MUST NOT configure app internals, and application-plane wiring MUST live **co-located with the stack it configures** (e.g. `stacks/<stack>/configure/`), run **post-deploy** (after the apps are healthy with keys pinned), and be owned by that stack rather than the global `provision/` tree.
- **FR-024**: Each app's API key and inter-app endpoint MUST be **deterministic and known at deploy time** (not randomly generated on first boot), so a clean redeploy reproduces the wiring without manual key exchange between apps.
- **FR-022**: The stack's total resource footprint MUST fit the Dell's memory budget, or the plan MUST explicitly document which stateless components run on the Mac to stay within it.

### Key Entities *(include if feature involves data)*

- **Request**: a household member's ask for a specific movie/show; drives acquisition and is the surface that shows availability; cleared on cascade delete.
- **Media item**: a movie or TV series/season/episode — its files on disk under `/srv/nfs/media`, its monitored entry in Radarr/Sonarr, and its representation in each media server's library. The unit that the cascade delete operates on.
- **Download**: an in-progress or seeding torrent in the download client, tied to a media item; must egress via VPN and be cleaned up on delete.
- **Quality profile / custom format set**: the code-defined rules (from the community standard) governing which releases are acceptable and which trigger upgrades.
- **Library**: the shared on-disk media tree, read by both media servers; the single source of truth that deletion mutates.
- **Indexer**: a configured source of releases, centrally managed and synced to the arr apps; may sit behind bot-protection.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A household member can go from "request a title" to "playing it" through the request page and a media-server app with **zero** manual file or app handling in between, for a title available on the configured indexers.
- **SC-002**: During active downloading, **0%** of the download client's traffic egresses over the home internet connection; with the VPN tunnel forced down, outbound download traffic is fully blocked and the observed egress IP is never the home public IP (Proton exit IP only).
- **SC-002a**: The download client reports a **connectable / open** listen port matching Proton's current forwarded port, and after a VPN gateway restart or a Proton port rotation the client's port re-syncs automatically within one update cycle with no operator action.
- **SC-003**: A single operator delete action removes a title from **all six** surfaces (disk, download client, arr app, Jellyfin, Plex, request app) within one refresh cycle, verified with **0** orphans remaining (no seeding torrent, no ghost library entry, no still-monitored auto-re-download).
- **SC-004**: **0** media items are ever removed without an explicit operator action over a sustained observation period (no time/watch/disk-triggered deletion occurs).
- **SC-005**: Re-running the delete action on an already-deleted or partially-deleted title leaves the system in the same fully-clean end state (idempotent) with no error that requires manual repair.
- **SC-006**: Importing a completed download consumes **no** additional library-sized disk beyond the download copy (hardlink confirmed), and seeding can continue after import.
- **SC-007**: An injected stalled/blocked download is automatically removed, blocklisted, and re-searched within one cleanup cycle, with no operator action.
- **SC-008**: The same title is simultaneously playable from both Jellyfin and Plex reading the same file, with only **one** copy of the media on disk.
- **SC-009**: Quality profiles in Radarr/Sonarr match the code-defined community standard immediately after deploy, and a second deploy makes no further changes (idempotent).
- **SC-010**: 100% of user-facing services are reachable at `https://<name>.ragnaforge.xyz` with valid TLS and listed on the Homepage dashboard.
- **SC-011**: On a clean rebuild from the repo, **all** inter-app connections (indexers→arr, download client→arr, subtitles→arr, request app→arr) are present with **zero** manual UI clicks — established by native sync plus the idempotent Ansible wiring play — and involve **no** custom scripts and **no** stale third-party tools. Re-running the wiring changes nothing (idempotent).

## Assumptions

- **Media server choice**: Both Jellyfin and Plex run against the same library (operator's explicit choice). Plex requires a Plex account and Plex Pass for hardware transcoding; Jellyfin's hardware transcoding is free. The plan will use the shared Intel QuickSync iGPU on the Dell for transcoding and account for Plex's account/Plex-Pass dependency.
- **Single request app**: One request application serves both players (a Jellyseerr-class app that supports Jellyfin **and** Plex), rather than running a separate request app per server, to keep one request surface (FR-016).
- **Deletion posture is manual-only**: No watch-state/age/disk automation deletes media (operator's explicit choice). Automated reclamation tools (e.g., rule-based cleaners) are deliberately excluded from this phase; the cascade action is the deletion mechanism.
- **Cascade mechanism is a dedicated off-the-shelf app, not scripts**: the operator explicitly rejected custom scripts/glue. A single maintained application (Maintainerr-class — the only mature cleanup tool that integrates **both Plex and Jellyfin** at once) performs the whole cascade: it deletes files from disk, unmonitors/removes in Radarr/Sonarr, removes the item from the download client (stops/removes the seeding torrent), and clears the request in Seerr, across both media servers. The operator's manual-only posture is met by using its **manual collection** mode (add the specific title to a "remove" collection) rather than automated age/watch/disk rules; the "single action" is "add the title to the delete collection," which the tool then enforces as the full cascade. Radarr/Sonarr remain the on-disk file authority the tool acts through; the plan decides the instance topology (one multi-server instance vs. one per server) and how the two servers reflect the removal (scheduled scan vs. triggered refresh).
- **Modern tool set (2026), per operator selection**: the stack includes the cross-service deletion app (Maintainerr-class — supports both Plex and Jellyfin, cascades to disk/arr/download-client/Seerr, manual-collection capable), unified queue cleanup (Cleanuparr-class), code-driven TRaSH quality profiles (Recyclarr/Configarr-class), missing-content/upgrade hunting (Huntarr-class), a modern bot-protection indexer proxy (Byparr-class, the FlareSolverr successor), and watch statistics (Jellystat/Tautulli-class) — in addition to the PLAN.md baseline (Gluetun + qBittorrent, Prowlarr, Radarr, Sonarr, Bazarr).
- **Downloads are torrent-based** via qBittorrent behind Gluetun, as in PLAN.md; Usenet (SABnzbd + Usenet indexers) is not in scope for this phase (may be added later as an additive download client).
- **Auto-wiring strategy is native-first, no scripts**: the bulk of inter-app configuration is done by maintained mechanisms — Prowlarr's first-party **application sync** auto-propagates indexers to Radarr/Sonarr; **Recyclarr/Configarr** apply quality profiles/custom formats from code; and each app's **API key is pinned via `mise` env** so downstream apps (Prowlarr, Jellyseerr, Bazarr, Maintainerr, the port-sync helper) are pointed at known endpoints at deploy time.
- **Buildarr is explicitly excluded**: it is the only fully-declarative tool for the *remaining* connections (download client into Radarr/Sonarr, Jellyseerr→arr links), but as of 2026 it is effectively unmaintained (last release 2023, last commit mid-2024) and would violate the north-star ("nothing that silently goes outdated"). The plan MUST NOT use or trial it.
- **Configuration is organized into three planes (organizing principle)**: work in this stack falls into three distinct lifecycle planes, and they MUST NOT be conflated under one "provisioning" bucket:
  1. **Machine plane** — turning a bare device into a fleet node (Docker, NFS, sysctl, users, Tailscale). Operates on the **OS over SSH**, runs once per host, rarely changes. Owned by **Ansible** (`provision/`). This plane MUST stay machine-only and MUST NOT touch any app's internal settings.
  2. **Deployment plane** — running the containers. Operates on **Compose stacks**, git-synced, on deploy. Owned by **Komodo**.
  3. **Application plane** — configuring settings *inside* the running apps (inter-app wiring). Operates on the apps' **HTTP APIs**, runs **post-deploy** (after apps are healthy with keys pinned), changes when apps are reconfigured. This is **not** provisioning and MUST live separately from `provision/`.
- **Application-plane wiring prefers the narrowest maintained tool per job, and is co-located with its stack**: indexers→arr use **Prowlarr native app-sync**; quality profiles use **Recyclarr/Configarr**; the genuine residual (qBittorrent as download client in Radarr/Sonarr; Jellyseerr→arr links; any Bazarr→arr / notification links) is a small **idempotent, post-deploy API step**. That residual wiring MUST live **next to the stack it configures** (e.g. `stacks/media/configure/` alongside the stack's `compose.yaml`), owned by the stack — **not** folded into the global machine-plane `provision/` tree. Its mechanism MAY reuse Ansible (the `uri` module is a fine idempotent API caller) or a lighter script-free per-stack runner — that is a plane-3 implementation detail for the plan; the organizing rule (co-located, post-deploy, idempotent, no bespoke scripts, no stale third-party tools like Buildarr) is what this spec fixes. Accepted tradeoff: hand-encoded API request bodies are somewhat app-version-sensitive, so a major app upgrade may require a payload update — a small, self-owned maintenance cost surfaced as a visible failure, with no dependency on an abandoned project.
- **Storage is ready**: Phase 4's verified `/srv/nfs` tree, ownership (`1000:1000`, setgid), and single-filesystem hardlink guarantee are in place and are the paths this phase mounts.
- **Edge is ready**: Phase 3's Traefik + wildcard TLS + AdGuard + Homepage are available for routing and dashboarding every service.
- **Proton VPN (paid plan) is the download egress**: the operator has a Proton VPN subscription; the download client egresses through it over WireGuard via Gluetun (Gluetun has native Proton provider support). The plan MUST enable Proton **port forwarding (NAT-PMP)** and keep the download client's listen port synced to the rotating forwarded port using off-the-shelf tooling (helper container or Gluetun's built-in port-forwarding command), never a hand-maintained script (FR-003a). Proton WireGuard credentials live in `.mise.toml`, never committed. (This replaces the generic "commercial VPN" placeholder in PLAN.md prerequisites.)
- **Consumers**: the operator (full control: config, request, delete, maintain) plus household/friends (browse, request, watch only). Friends' network access is fenced in Phase 7, not here.

## Out of Scope

- **Automated media reclamation** (deleting by watch-state, age, rating, duplicates, or disk pressure) — explicitly excluded per the manual-only choice; may be reconsidered in a later phase.
- **Usenet** download path (SABnzbd + Usenet indexers) — torrent-only for this phase.
- **Music/audiobooks/e-books** (Lidarr/Readarr and their libraries) — only movies and TV are in scope.
- **Family/friends network access, VPN onboarding, and Fire TV delivery** — that is Phase 7; this phase only ensures the media services exist and are reachable on LAN/Tailscale.
- **Backups/snapshots** of media or app config — Phase 9.
- **Monitoring/alerting** for the media services — Phase 8 (though services expose whatever the standard dashboard/health surfaces already provide).
- **Attaching additional physical capacity** (mergerfs + USB) — documented as a future path in Phase 4, not stood up here.
