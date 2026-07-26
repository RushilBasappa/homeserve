# Feature Specification: Self-Hosted Headscale VPN (replace wg-easy; retire Tailscale SaaS)

**Feature Branch**: `011-headscale-vpn`

**Created**: 2026-07-25

**Status**: Draft

**Input**: User description: "Get rid of the wg-easy WireGuard that was failing (can't connect). Completely shift to Headscale. Do NOT delete Tailscale — but Tailscale may be stopped. Make Headscale production-grade with best practices, and tell me which ports to open so anyone outside the network can do the initial handshake, config validation, and then smooth connections."

## Overview

The fleet currently has **two** remote-access VPNs: **Tailscale** (owner-only, using Tailscale's hosted control plane) and **wg-easy** (a self-hosted WireGuard server for family/friends). wg-easy is unreliable — remote clients frequently fail to connect (carrier CGNAT UDP throttling, mapping expiry, brittle single-UDP-port path). This feature **removes wg-easy entirely** and consolidates **all** remote access — owner and guests alike — onto a **self-hosted Headscale** control server driving the standard Tailscale clients.

Headscale becomes the fleet's own coordination server, so the network no longer depends on Tailscale's SaaS control plane for the primary path. The **Tailscale client software and the existing Tailscale account/tailnet are preserved as a fallback** (the running connection to Tailscale's SaaS may be stopped once Headscale is proven), giving a clean rollback path if Headscale has problems.

The end-user experience for guests must stay as simple as wg-easy's was (install one app, tap a link / paste one key, done), while giving reliable connectivity through automatic NAT traversal with a relay fallback — which WireGuard-only wg-easy could not do.

## Clarifications

### Session 2026-07-25

- Q: Where should the Headscale control server + its public entry point live? → A: **Dell + home router forward ("GO" path)** — Headscale runs on the Dell behind Traefik at `headscale.ragnaforge.xyz`; the xFi router forwards **443/tcp + 3478/udp** to the Dell. The relay-VPS ("NO-GO") path remains the documented CGNAT fallback (FR-016).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Owner reaches the fleet from anywhere via Headscale (Priority: P1)

The homelab owner, on a laptop or phone away from home (hotel WiFi, cellular, a friend's house), connects to the fleet and reaches every internal app by its friendly `*.ragnaforge.xyz` name over HTTPS — exactly as at home — using a device enrolled in the **self-hosted Headscale** tailnet, with **no dependency on Tailscale's hosted control plane**.

**Why this priority**: The owner's own remote access is the most-used path and the one that must never regress. It is also the smallest, most controllable slice (one enrolled device) and proves the control server, DNS push, and subnet routing end-to-end before any guest is onboarded.

**Independent Test**: Enroll the owner's laptop against Headscale, stop the Tailscale-SaaS connection, take the laptop off the home LAN (tether to a phone), and confirm it (a) establishes a tunnel, (b) resolves `whoami.ragnaforge.xyz` to the internal address, and (c) loads it over HTTPS with the valid wildcard cert.

**Acceptance Scenarios**:

1. **Given** an owner device enrolled against Headscale and physically off the home network, **When** it comes online, **Then** it establishes an encrypted tunnel to the fleet within seconds without any manual key exchange.
2. **Given** the connected owner device, **When** it opens `https://<app>.ragnaforge.xyz`, **Then** the internal resolver answer is used, the app loads, and the certificate is valid (padlock, no warning).
3. **Given** the owner device is on a network that blocks direct peer-to-peer UDP, **When** it connects, **Then** traffic is automatically carried over a relay and the app still loads (degraded throughput, not a failure).
4. **Given** Headscale is the primary path, **When** the owner checks connectivity, **Then** no active session depends on Tailscale's hosted coordination server.

---

### User Story 2 - A non-technical family member / friend is onboarded and connects reliably (Priority: P1)

A non-technical guest is given access. They install the standard client app, follow a single simple step (open a login link, or paste/scan one pre-authorized key the owner sends them), and thereafter reach the specific apps the owner shares with them — reliably, including from a phone on cellular, which is exactly where wg-easy failed.

**Why this priority**: Replacing the *failing* wg-easy for guests is the core motivation. Reliable guest connectivity on cellular/CGNAT is the headline improvement over WireGuard-only.

**Independent Test**: Send a guest a pre-authorized enrollment, have them complete it on a phone using only the app + the link/key, then verify from a cellular connection (no WiFi) that they reach a shared app and cannot reach anything not shared with them.

**Acceptance Scenarios**:

1. **Given** the owner generates a guest enrollment (a pre-authorized key or login link), **When** the guest follows the single documented step in the client app, **Then** their device joins the tailnet with no further owner intervention.
2. **Given** an enrolled guest device on cellular data with no WiFi, **When** they open a shared app's friendly name, **Then** it loads over HTTPS — where wg-easy previously failed to connect.
3. **Given** an enrolled guest, **When** they attempt to reach an app or host not in their shared scope, **Then** access is denied by policy.
4. **Given** a guest enrollment intended to be temporary, **When** its validity period elapses (or the owner revokes it), **Then** that device can no longer connect.

---

### User Story 3 - wg-easy is decommissioned and Tailscale is preserved as a stopped fallback (Priority: P2)

The operator removes the wg-easy stack and its public exposure, and reconfigures the home network's inbound so the old single WireGuard UDP port is closed and only the Headscale-required ports are open. The Tailscale client and existing tailnet configuration are left in place but the running SaaS-connected session is stopped, so the fleet can be reverted to Tailscale quickly if Headscale misbehaves.

**Why this priority**: Cleanup and a documented rollback path make the migration safe to keep, but they follow proving the two connectivity paths (P1) work.

**Independent Test**: Confirm wg-easy is gone (stack removed, admin UI unreachable, old UDP port no longer forwarded), that the fleet still works entirely via Headscale, and that Tailscale can be restarted on the Dell to restore the old owner path within minutes if needed.

**Acceptance Scenarios**:

1. **Given** Headscale is proven for both owner and guest, **When** the operator decommissions wg-easy, **Then** the wg-easy stack, its admin UI, and its public port forward are all removed from the fleet and its config.
2. **Given** the migration is complete, **When** the operator inspects the fleet, **Then** the Tailscale client is still installed and its tailnet identity is intact, but its running session is stopped and documented as the fallback.
3. **Given** a need to roll back, **When** the operator restarts Tailscale on the Dell, **Then** the previous owner remote-access path is restored without re-provisioning.

---

### Edge Cases

- **Direct path blocked**: A client is on a network where NAT traversal fails (STUN blocked, symmetric NAT, carrier CGNAT). The connection MUST fall back to relay so the app still loads; the system MUST NOT hard-fail.
- **Control server unreachable**: If the Headscale control server is down, already-connected peers should continue to pass traffic on existing direct/relay paths for as long as their keys are valid; only new enrollments and re-key events fail until it recovers. This is a single point of failure that MUST be documented, and its state (keys/DB) MUST be treated as protected fleet state.
- **Enrollment key expiry / node key expiry**: A device whose node key expires must be re-authenticated; the guest onboarding doc MUST make this recoverable without deep networking knowledge.
- **Config validation**: Before the control server is exposed publicly, its configuration MUST be validatable so a broken config is caught before external clients depend on it.
- **CGNAT at home (no inbound)**: If the home network cannot accept the required public inbound ports, the fleet MUST still be reachable via the fallback relay path (analogous to the existing relay VPS recipe), rather than requiring home port-forwarding.
- **IPv6 exposure**: Opening the new public ports MUST NOT re-expose the whole host on public IPv6 (a known hazard on the Xfinity gateway). Published entry points bind to the intended interface only.
- **Certificate & friendly names**: Remote clients continue to receive the internal resolver and subnet route so `*.ragnaforge.xyz` resolves and validates exactly as on the LAN; the migration MUST NOT change the certificate story.
- **Two clients, same person**: The owner running both the old Tailscale session and Headscale during cutover MUST not create a routing conflict; the cutover order MUST be defined.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The fleet MUST run a self-hosted Headscale control server as the coordination plane for all remote access (owner and guests).
- **FR-002**: The system MUST remove the wg-easy stack entirely — its container/stack definition, its admin UI exposure, and its public port forward.
- **FR-003**: The system MUST preserve the Tailscale client software and the existing Tailscale tailnet identity on the Dell; it MUST NOT delete or uninstall them. Stopping the running Tailscale session is permitted.
- **FR-004**: Remote clients MUST use the standard official Tailscale client applications, pointed at the self-hosted control server (no custom client).
- **FR-005**: The owner MUST be able to enroll a device against Headscale and reach all internal apps by their `*.ragnaforge.xyz` names over HTTPS with a valid certificate, from any external network.
- **FR-006**: The owner MUST be able to issue a guest enrollment (pre-authorized key or login link) that a non-technical person can complete with only the client app and a single copy/paste or tap — no command line.
- **FR-007**: The system MUST push the internal DNS resolver and the LAN subnet route to connected clients so remote devices resolve and reach apps exactly like LAN devices (preserving the existing friendly-name + wildcard-cert experience).
- **FR-008**: Connectivity MUST automatically attempt a direct peer-to-peer path and fall back to a relay when direct is impossible, so clients on CGNAT/cellular still connect (the reliability gap wg-easy could not close).
- **FR-009**: The system MUST enforce per-user/per-device access scope (policy) so guests reach only the apps/hosts shared with them and not the whole fleet.
- **FR-010**: Guest enrollments MUST support expiry and revocation by the owner.
- **FR-011**: The Headscale configuration MUST be validatable before public exposure (a config/preflight check that fails closed on a broken config).
- **FR-012**: The system MUST document the exact set of public ports to open, their protocol, and their purpose (initial handshake/enrollment, config/control validation, relay, and direct connections) — see "Public Ports" below.
- **FR-013**: The public control-plane entry point MUST be served over TLS with a valid certificate and MUST support the client control protocol's connection-upgrade (long-lived streaming) requirement.
- **FR-014**: The control server's state (keys, node registrations, database, TLS material, pre-auth keys) MUST be treated as protected fleet state with a defined persistence and backup location; secrets MUST NOT be committed to the repo.
- **FR-015**: Opening the new public ports MUST NOT re-expose unrelated host services on public IPv6; entry points MUST bind to the intended interface only.
- **FR-016**: The system MUST provide a documented fallback for a home network that cannot accept public inbound (CGNAT/uncooperative gateway), reusing the relay-VPS pattern so remote access works with no home inbound port.
- **FR-017**: The migration MUST provide a documented rollback: restarting Tailscale on the Dell restores the prior owner path without re-provisioning.
- **FR-018**: The whole change MUST be reproducible from code (stack definition, orchestration declaration, host prerequisites, runbook) consistent with the repo's portability goal — no undocumented manual steps.
- **FR-019**: Operator-facing documentation MUST include a guest onboarding guide and a runbook covering enrollment, key rotation/expiry recovery, control-server backup/restore, and the port/firewall changes.

### Public Ports (informative — answers "what ports to open")

These are the ports that must be reachable from the public internet for external clients to enroll, validate, and connect. Per Clarifications Q1, they are opened by **forwarding on the home xFi router to the Dell** (the "GO" path); the relay-VPS path (FR-016) is the fallback if the home network cannot forward them.

| Port | Protocol | Purpose | Public? |
|------|----------|---------|---------|
| **443** | TCP | Control-plane HTTPS: initial handshake, node enrollment/login, config/key validation, control stream, **and** the embedded relay (DERP over HTTPS/WebSocket). This is the one port every external client must reach. | **Yes** |
| **3478** | UDP | STUN — NAT traversal probing so clients can establish **direct** peer-to-peer links instead of relaying everything. If blocked anywhere in the path, all traffic falls back to relay (works, but slower). | **Yes** |
| **80** | TCP | Optional: HTTP for client captive-portal detection and, if ever used, ACME HTTP-01. Not required when TLS is provisioned via the existing DNS-01 wildcard. | Optional |
| **41641** | UDP | Optional: default client port for **direct** WireGuard peer connections; forwarding it improves the odds of a direct link to home-side nodes. Not required for the handshake. | Optional |

> Contrast with the old design's single `51820/udp`. Headscale's mandatory public surface is **443/tcp + 3478/udp**. Because 443/tcp must now be publicly reachable, the security posture of the fleet's front door changes and MUST be reviewed (previously 443 was never router-forwarded). See Assumptions.

### Key Entities

- **Headscale control server**: The self-hosted coordination plane; owns the tailnet's node registry, keys, DNS/route push, and policy. Holds protected state.
- **Tailnet node**: An enrolled device (owner or guest) identified by a node key, with an assigned tailnet address and a scope.
- **User / namespace**: The identity a node belongs to (e.g., `owner`, `guests`), the unit ACL policy is written against.
- **Pre-authorized key / login link**: The credential the owner hands a guest to enroll a device; carries validity/expiry and optional reusability.
- **Relay (DERP)**: The fallback path that carries traffic when a direct peer-to-peer link cannot be formed.
- **Access policy (ACL)**: Rules mapping users/devices to the apps/hosts they may reach.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From an external network (cellular, no home WiFi), an enrolled owner device reaches any internal `*.ragnaforge.xyz` app over HTTPS with a valid certificate in under 30 seconds from cold connect.
- **SC-002**: A non-technical guest completes enrollment on a phone using only the client app plus one link/key — no terminal — in under 5 minutes, with no live help beyond the written guide.
- **SC-003**: On a client where direct peer-to-peer is impossible (blocked STUN/CGNAT), the connection still succeeds via relay in 100% of tests — the wg-easy failure mode is eliminated.
- **SC-004**: 0 remote sessions depend on Tailscale's hosted control plane once cutover is complete; the primary path is fully self-hosted.
- **SC-005**: The set of public ports the operator must open is documented in exactly one authoritative place and matches what is actually exposed (verifiable by an external port scan showing only the intended ports open).
- **SC-006**: After decommission, wg-easy's admin UI and its old public UDP port are unreachable (verified externally and on-LAN).
- **SC-007**: Rolling back to Tailscale (restart on the Dell) restores the owner path in under 10 minutes with no re-provisioning.
- **SC-008**: The entire deployment can be reproduced from the repo on a fresh host by following the runbook, with no manual step that isn't written down.
- **SC-009**: Opening the new ports introduces no additional host services reachable on the public IPv6 address (verified by an external v6 scan showing no new open services).

## Assumptions

- **Deployment location** (confirmed, Q1): Headscale runs **on the Dell**, fronted by the existing Traefik reverse proxy at a dedicated name (`headscale.ragnaforge.xyz`) on **443/tcp**, with **3478/udp** published for STUN — with the **home xFi router forwarding 443/tcp + 3478/udp** to the Dell (the "GO" path, mirroring the existing DDNS/Traefik setup). The relay-VPS ("NO-GO") path is the documented fallback (FR-016).
- Forwarding **443/tcp** publicly is a deliberate posture change from the old "443 is never forwarded" rule; it is accepted as the cost of a control plane that must be publicly reachable, and is mitigated by keeping the surface to the Headscale vhost + valid TLS. Reviewed under FR-015 (no v6 host exposure) and the existing Xfinity "Typical Security" IPv6 rule.
- The **embedded relay** in Headscale is sufficient for a small tailnet (well under ~50 active nodes); a standalone relay is out of scope for v1.
- The existing internal resolver (AdGuard, `10.0.0.70`) and wildcard-cert / Traefik edge are reused unchanged; this feature only changes *how remote clients get onto the network*, not steps 1 and 3 of the "name → address → app" flow.
- The official Tailscale clients are acceptable on all target devices (desktop + mobile + Fire TV where applicable); no unusual platform lacks a client.
- Host IP forwarding and any required kernel/network prerequisites on the Dell are already satisfied (as they were for wg-easy) or will be codified alongside this change.
- "Production-grade" here means for a personal homelab serving the owner + a handful of family/friends — highly reliable and reproducible, not a multi-tenant commercial control plane.
- Secrets (pre-auth keys, DB, private keys) live in the existing gitignored/`mise` secret mechanism and on Dell-local protected volumes, consistent with the fleet's golden rule that state lives on the Dell.

## Dependencies

- Reuses the existing **Traefik** edge, **AdGuard** internal DNS, wildcard **TLS** (Cloudflare DNS-01), and **cloudflare-ddns** (for the home public-IP name) — same components as the current design.
- Reuses the existing **relay-VPS recipe** (`relay/`) for the CGNAT fallback, re-pointed at the Headscale tailnet instead of the Tailscale SaaS tailnet.
- Depends on the home gateway being able to forward **443/tcp + 3478/udp** for the GO path (validated by the existing preflight concept).
