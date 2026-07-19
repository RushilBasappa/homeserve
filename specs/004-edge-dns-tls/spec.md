# Feature Specification: Phase 3 — Edge, DNS & TLS

**Feature Branch**: `004-edge-dns-tls`

**Created**: 2026-07-19

**Status**: Draft

**Input**: User description: "start with next phase?"

## Overview

Phase 2 turned the two Debian hosts into a centrally managed fleet: the operator
declares stacks in git and deploys them to either node from Komodo Core alone.
But a deployed stack today is only reachable by IP and raw port on the LAN, over
plain HTTP, with no memorable name. Phase 3 builds the **edge**: the layer that
gives every stack a stable hostname under `ragnaforge.xyz`, a valid browser-trusted
HTTPS certificate, and a single front door — so a stack becomes an app the moment
it is deployed.

Concretely this phase stands up these capabilities as Komodo-deployed stacks:

- A **reverse proxy** (Traefik) that discovers stacks by their Docker labels and
  routes `https://<name>.ragnaforge.xyz` to the right container, redirecting all
  plain HTTP to HTTPS.
- **Wildcard TLS** for `*.ragnaforge.xyz` from Let's Encrypt, obtained and renewed
  automatically via a **Cloudflare DNS-01** challenge (no inbound port needed, and
  one cert covers every current and future subdomain).
- **Internal DNS** (AdGuard Home) that resolves `*.ragnaforge.xyz` to the edge host,
  with LAN-wide ad-blocking as a bonus, and that is handed to VPN clients so they
  resolve the same names.
- **Dynamic DNS** (Cloudflare DDNS) that keeps the public `vpn.ragnaforge.xyz`
  record pointed at the home's current public IP.
- A **secondary remote-access VPN** (WireGuard / wg-easy) for family/friends,
  reached at `vpn.ragnaforge.xyz` through **exactly one** public UDP port
  (**51820**). A **preflight** first checks whether the basic Xfinity gateway can
  actually host that port (real public IP, not CGNAT); if it can, the port is
  forwarded straight to the Dell — if not, a small cloud relay stands in. Either
  way this is the phase's **only** public exposure.

There are **two VPN paths** into the edge: **Tailscale** is the operator/admin path
(mesh, needs no exposed port) and **WireGuard** is the family/friends path (the one
exposed port). A connected client reaches the edge and its `*.ragnaforge.xyz` names
over whichever path it is on; the internal resolver answers the same names on both.
The phase's front door is a **Homepage** dashboard at `https://home.ragnaforge.xyz`
that links out to every app.

This phase delivers the **edge and private remote-access capability**, not the
end-user applications behind it (media, photos, budgeting, etc. are Phases 5–6). It
is proven when a stack deployed through the Phase 2 workflow is reachable at a
friendly HTTPS URL with a browser-trusted certificate, Homepage lists it, and a
remote device reaches it over **each** VPN path — while a scan from the public
internet finds only the single WireGuard port open. The "user" throughout is the
**operator** reproducing and running the server, anyone on the LAN opening an app
URL, and a **remote family/friend** connecting over the secondary VPN.

## Clarifications

### Session 2026-07-19

- Q: Should TLS stay on Let's Encrypt, or is there a more modern approach? → A:
  Keep Let's Encrypt via ACME DNS-01 (still the 2026 standard; ZeroSSL / Google
  Trust Services are peer ACME CAs, not replacements), but design **lifetime-
  agnostic**: rely on fully automatic renewal driven by ARI (ACME Renewal Info)
  where the client supports it, with no hardcoded certificate lifetime — so LE's
  move to shorter certs (45-day tlsserver profile from 2026-05-13, 64-day default
  from 2027, opt-in 6-day short-lived) requires no rework. Not opting into the
  6-day short-lived profile (unnecessary blast-radius for a home lab).
- Q: Public exposure boundary for this phase — nothing exposed (defer secondary
  VPN + port to a later phase), or pull the secondary VPN and its exposed port
  into Phase 3? → A: **Pull it in.** Phase 3 now also stands up the **secondary
  remote-access VPN** (WireGuard / wg-easy) and exposes **exactly one** public
  port for it (**UDP 51820**, router-forwarded to the Dell at `10.0.0.70`).
  `vpn.ragnaforge.xyz` (kept current by Cloudflare DDNS) is that VPN's public
  endpoint name. Tailscale remains the operator/admin path and needs **no** exposed
  port. Everything else — apps, dashboard, resolver, all admin UIs — stays
  LAN/Tailscale-only. Two VPN paths total: **Tailscale** (operator, primary) and
  **WireGuard** (family/friends, secondary); a client reaches the edge and its
  `*.ragnaforge.xyz` names over whichever it is connected through.
- Q: Domain registrar / DNS split → A: Registrar is **Porkbun**; authoritative DNS
  is delegated to **Cloudflare** (so DNS-01 issuance and DDNS both run against the
  Cloudflare zone — the registrar is not involved at runtime). Canonical spelling
  is **`ragnaforge.xyz`**.
- Q: What address does the internal resolver return for `*.ragnaforge.xyz`, and how
  do off-LAN (VPN) clients reach it? → A: **Single address + subnet routing.** The
  resolver always returns the edge's LAN IP (`10.0.0.70`) for every client; the Dell
  advertises/routes the `10.0.0.0/24` subnet to **both** VPNs (Tailscale and
  WireGuard) so remote clients reach that address. One uniform answer, one cert
  target — no split-horizon.
- Q: (resolves the prior open marker) Is the edge / certificate store pinned to one
  node, or reachable from whichever node runs the edge? → A: **Pinned to the Dell
  (`10.0.0.70`).** Implied by the two answers above — the resolver always returns
  the Dell's IP and the one public port forwards to the Dell — and consistent with
  the "stateful → Dell" rule. The edge, its wildcard-cert store, the resolver, and
  the secondary VPN all run on the Dell.
- Q: Given a basic **Xfinity** gateway (dynamic IP, possible CGNAT, sometimes-flaky
  port-forward), how is the secondary VPN's public reachability handled? → A:
  **Verified gate with a fallback, and the checks run first.** Before building the
  secondary VPN, a **preflight** confirms the connection can host a public UDP
  endpoint: real public IPv4 (not CGNAT), UDP 51820 forwardable on the xFi gateway,
  `vpn.ragnaforge.xyz` resolving to that IP, and an external WireGuard handshake
  succeeding. Only if all pass does the direct port-forward path proceed. If any
  fail (CGNAT / blocked / unstable), fall back to a small always-on **cloud relay**
  (a VPS with a public IP tunnelling UDP to the Dell over Tailscale) so the family
  VPN still ships. Tailscale (operator path) is unaffected either way. Note:
  Xfinity's default LAN is already `10.0.0.1/24`, matching the assumed
  `10.0.0.0/24`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reach any app at a friendly HTTPS name (Priority: P1)

As a person on the home network, I open `https://home.ragnaforge.xyz` (or any
`https://<app>.ragnaforge.xyz`) in a browser and the page loads with a valid,
browser-trusted certificate — no IP addresses, no port numbers, no security
warning to click through.

**Why this priority**: This is the phase's headline deliverable and the reason
every later app phase is worth doing. Without a friendly, trusted HTTPS front
door, each app is a raw `IP:port` that only the operator can find and that browsers
flag as insecure.

**Independent Test**: With the edge stack deployed, deploy a trivial web stack
(e.g. the existing `whoami`) carrying the routing labels, then open its
`https://<name>.ragnaforge.xyz` URL from a LAN browser and confirm the page loads
with a valid certificate and no warning.

**Acceptance Scenarios**:

1. **Given** the reverse proxy and a labelled stack are running, **When** a LAN
   user opens `https://<name>.ragnaforge.xyz`, **Then** the correct app responds
   over HTTPS with a certificate the browser trusts (no warning).
2. **Given** a user opens the same name over plain `http://`, **When** the request
   reaches the edge, **Then** it is redirected to the `https://` equivalent.
3. **Given** a request for a hostname no stack claims, **When** it reaches the
   edge, **Then** the user gets a clear "not found" response rather than being
   routed to an unrelated app.

---

### User Story 2 - Publishing a new app is just labels + a DNS name (Priority: P1)

As the operator, I make a newly deployed stack reachable by adding routing
**labels** to its Compose definition (and, if it is a brand-new name, one DNS
entry) — with no edits to the proxy's own configuration and no manual certificate
work. The wildcard certificate already covers the new subdomain.

**Why this priority**: Every subsequent phase (media, apps, dashboards) publishes
apps through this exact path. If publishing an app required hand-editing proxy
config or minting a per-app certificate, the whole "a competent friend could
reproduce it" north star breaks down and each later phase inherits toil.

**Independent Test**: Add routing labels to a second stack and deploy it through
the Phase 2 workflow; confirm it becomes reachable at its HTTPS name within
seconds without touching the proxy's configuration or requesting a new
certificate.

**Acceptance Scenarios**:

1. **Given** a running edge, **When** the operator deploys a new labelled stack,
   **Then** its route becomes active automatically (proxy config is not
   hand-edited).
2. **Given** the wildcard certificate for `*.ragnaforge.xyz` is present, **When**
   a new subdomain is served, **Then** it is covered by that existing certificate
   with no new issuance step.
3. **Given** a stack is removed, **When** it stops running, **Then** its route
   stops responding and no stale route lingers.

---

### User Story 3 - Automatic, browser-trusted certificates that renew themselves (Priority: P1)

As the operator, the edge obtains and **renews** a wildcard certificate for
`*.ragnaforge.xyz` from a public certificate authority automatically, proving
domain ownership through a **DNS challenge** — so I never manually request,
install, or renew a certificate, and nothing breaks when a cert nears expiry.

**Why this priority**: A trusted certificate is what separates "loads over HTTPS"
(US1) from "loads with a scary warning." Doing it via a DNS challenge means no
inbound port has to be opened for issuance and a single wildcard covers every
subdomain, which is what makes US2 zero-touch.

**Independent Test**: Bring up the edge with no certificate present and confirm it
obtains a valid `*.ragnaforge.xyz` certificate unattended; inspect the served
certificate's issuer and validity, and confirm the renewal mechanism is
configured to renew before expiry without manual action.

**Acceptance Scenarios**:

1. **Given** valid DNS-provider credentials and no cached certificate, **When** the
   edge starts, **Then** it obtains a valid wildcard certificate for
   `*.ragnaforge.xyz` from the certificate authority unattended.
2. **Given** an issued certificate approaching expiry, **When** the renewal window
   arrives, **Then** the edge renews it automatically with no operator action and
   no user-visible interruption.
3. **Given** the DNS-provider credentials are missing or invalid, **When**
   issuance is attempted, **Then** it fails with a clear, logged error and the
   edge does not silently serve an untrusted or self-signed certificate in its
   place.

---

### User Story 4 - Names resolve on the LAN (and can follow VPN clients) (Priority: P1)

As a person on the home network, `*.ragnaforge.xyz` names resolve to the edge host
on the LAN so the friendly URLs actually reach home instead of the public
internet — and the same resolver can be handed to VPN clients so remote devices
resolve the same names. As a bonus, the resolver blocks ads network-wide.

**Why this priority**: Routing (US1/US2) and certificates (US3) are useless if a
browser can't turn `home.ragnaforge.xyz` into the edge's address. Internal
resolution is the missing half of "open the URL and it just works," and pushing it
to VPN clients is what lets later remote-access phases reuse the same names.

**Independent Test**: Point a LAN device at the internal resolver and confirm
`*.ragnaforge.xyz` resolves to the edge host's LAN address while public names still
resolve normally; confirm a known ad/tracker domain is blocked.

**Acceptance Scenarios**:

1. **Given** a device using the internal resolver, **When** it looks up any
   `<name>.ragnaforge.xyz`, **Then** it receives the edge host's LAN address.
2. **Given** the same device, **When** it looks up an ordinary public domain,
   **Then** it resolves normally (the resolver is not a walled garden).
3. **Given** a domain on the blocklist, **When** it is looked up, **Then** it is
   blocked rather than resolved.
4. **Given** a VPN client configured to use this resolver, **When** it looks up a
   `ragnaforge.xyz` name, **Then** it resolves to the edge without being defeated
   by DNS-rebind protection.

---

### User Story 5 - One front door lists every app (Priority: P2)

As the operator (and family on the LAN), I open a single dashboard at
`https://home.ragnaforge.xyz` that lists the running apps with links, so people
have one memorable place to start instead of memorizing each app's subdomain.

**Why this priority**: Real convenience and the phase's named deliverable URL, but
subordinate to actually being able to reach apps (US1) and publish them (US2); the
dashboard is a directory over capabilities that must already exist.

**Independent Test**: Open `https://home.ragnaforge.xyz` and confirm it loads over
valid HTTPS and shows a working link to at least one deployed app.

**Acceptance Scenarios**:

1. **Given** the edge and dashboard are running, **When** a user opens
   `https://home.ragnaforge.xyz`, **Then** the dashboard loads over trusted HTTPS.
2. **Given** apps are published behind the edge, **When** the dashboard is viewed,
   **Then** it shows entries linking to their HTTPS URLs.

---

### User Story 6 - Public DDNS record tracks the home IP (Priority: P3)

As the operator, a dynamic-DNS updater keeps the public `vpn.ragnaforge.xyz`
record pointed at the home's current public IP address, so the secondary VPN's
endpoint stays reachable even when the ISP changes the address.

**Why this priority**: It underpins the secondary VPN (US8) — that VPN's clients
dial `vpn.ragnaforge.xyz`, so the record must track the real IP — but it is
plumbing the end user never sees directly, so it stays low priority relative to the
edge itself.

**Independent Test**: Change (or simulate a change to) the observed public IP and
confirm the updater revises the `vpn.ragnaforge.xyz` record to match within its
configured interval.

**Acceptance Scenarios**:

1. **Given** the updater is running, **When** the home's public IP changes,
   **Then** the `vpn.ragnaforge.xyz` record is updated to the new address within
   the configured interval.
2. **Given** the public IP is unchanged, **When** the updater runs, **Then** it
   makes no unnecessary change.

---

### User Story 7 - Preflight: confirm the home can host a public VPN endpoint (Priority: P2, first step of the VPN slice)

As the operator, **before** I build the secondary VPN I run a set of connectivity
checks to learn whether my basic Xfinity gateway can actually host a public UDP
endpoint — a real public IPv4 (not CGNAT), a workable port-forward, DDNS resolving
to it, and a successful external handshake — so I choose the direct port-forward
path or the cloud-relay fallback **knowingly**, instead of discovering a dead end
after building everything.

**Why this priority**: It is the explicit **first step** of the secondary-VPN slice
(US8) — US8's whole reachability design branches on its result. It carries no
end-user value on its own, but skipping it risks building the VPN against a path
Xfinity silently blocks, so it gates US8.

**Independent Test**: Run the checks and produce a clear go/no-go: is the WAN IP a
real public address (not in a CGNAT range), does an external probe reach a
test-forwarded UDP 51820, and does `vpn.ragnaforge.xyz` resolve to that IP? Confirm
the result unambiguously selects direct-forward vs. relay.

**Acceptance Scenarios**:

1. **Given** the operator runs the preflight, **When** the WAN IP is a real public
   IPv4 and UDP 51820 is reachable from outside, **Then** the check reports GO for
   the direct port-forward path.
2. **Given** the WAN IP is CGNAT (shared / carrier-NAT range) or the forward is
   unreachable, **When** the preflight runs, **Then** it reports NO-GO for
   direct-forward and selects the cloud-relay fallback, with a clear reason.
3. **Given** an inconclusive or intermittent result, **When** the preflight runs,
   **Then** it does not report a false GO — the VPN build waits until the path is
   confirmed rather than proceeding on an unverified assumption.

---

### User Story 8 - Remote family/friend reaches the apps over the secondary VPN (Priority: P2)

As a remote family member or friend, I import a WireGuard config that points at
`vpn.ragnaforge.xyz`, connect from anywhere on the internet, and then reach the
home's apps at their `https://<name>.ragnaforge.xyz` URLs — resolving the same
names and getting the same trusted certificates as someone on the LAN — even though
only one port is open to the internet. Whether that endpoint is reached by a direct
xFi port-forward or via the cloud-relay fallback is decided by the preflight (US7)
and is invisible to me: the config and the experience are the same either way.

**Why this priority**: This is the scope the operator pulled into this phase: a
private way for non-technical people to reach the lab without exposing every app.
It sits below the core edge (US1–US4) because those must exist first for there to
be anything to reach, but above the pure DDNS groundwork (US6), which now serves
this VPN's endpoint name.

**Independent Test**: From a device off the home LAN and off Tailscale, import a
fresh WireGuard config, connect via `vpn.ragnaforge.xyz`, and confirm it resolves
and loads at least one `https://<name>.ragnaforge.xyz` app over a trusted
certificate; separately, scan the public IP and confirm only UDP 51820 responds.

**Acceptance Scenarios**:

1. **Given** the secondary VPN is up and the router forwards its one port, **When**
   a remote client connects with a valid config via `vpn.ragnaforge.xyz`, **Then**
   the tunnel establishes and the client can reach the edge.
2. **Given** a connected remote client using the internal resolver, **When** it
   opens `https://<name>.ragnaforge.xyz`, **Then** the name resolves to the edge
   and the app loads over a browser-trusted certificate.
3. **Given** the home's public IP, **When** it is port-scanned from the internet,
   **Then** only the single WireGuard UDP port is open and no app, dashboard,
   resolver, or admin UI is directly reachable.
4. **Given** the secondary VPN's admin UI (wg-easy), **When** access is attempted
   from off-LAN/off-Tailscale, **Then** it is not reachable (admin bound to
   LAN/Tailscale only, never the forwarded port).

---

### Edge Cases

- **Certificate authority rate limits / issuance failure**: repeated restarts must
  not burn the CA's issuance quota; the edge should reuse a cached certificate and
  back off rather than hammer issuance. The edge and its certificate store are
  **pinned to the Dell** (`10.0.0.70`), so the persisted cert always lives on one
  node — no cross-node cert reachability to arrange.
- **Two stacks claim the same hostname**: a duplicate route must resolve
  deterministically (or be flagged) rather than flapping between apps.
- **Edge host down**: while the edge host is offline, all `*.ragnaforge.xyz` names
  are unreachable — this is a single front-door dependency the operator accepts;
  it should fail as a clear connection error, not a certificate warning.
- **Internal resolver down**: if the internal DNS resolver is unavailable, name
  resolution for both `ragnaforge.xyz` and general browsing degrades — clients
  should have a defined fallback behavior rather than losing all DNS.
- **A stack exposes no HTTP service** (e.g. a background worker): it simply carries
  no routing labels and is not published — the edge must ignore it, not error.
- **Request for `home.ragnaforge.xyz` before any app is deployed**: the dashboard
  should still load and simply show no/known entries.
- **Secret (DNS-provider API token) missing at deploy**: the deploy must fail
  clearly (consistent with the Phase 2 secret-hygiene rule), not start an edge
  that can never obtain a certificate.
- **Edge address differs by path**: `10.0.0.70` is the edge on the LAN, but a
  remote WireGuard or Tailscale client is not on `10.0.0.0/24`. Resolved: the
  resolver returns `10.0.0.70` to **every** client and the Dell routes the
  `10.0.0.0/24` subnet to both VPNs, so remote clients reach that one address. If
  subnet routing is off for a given VPN, that VPN's clients resolve the name but
  cannot connect — which must surface as a routing failure, not a wrong answer.
- **Only one port is forwarded**: exactly one public port (UDP 51820) may be
  router-forwarded. Any admin UI (wg-easy, resolver, proxy) reachable on that port
  or otherwise from the internet is a defect — admin surfaces bind to
  LAN/Tailscale only.
- **Remote client without the internal resolver**: a VPN client that does not use
  AdGuard cannot resolve `*.ragnaforge.xyz`; the VPN config MUST push the internal
  resolver so names work, rather than silently failing to resolve.
- **ISP CGNAT / no inbound**: if Xfinity does not grant a real inbound public IP (or
  blocks the forward), the preflight (US7) MUST detect it and the design MUST switch
  to the cloud-relay fallback (FR-022) rather than silently failing — the secondary
  VPN still ships. Tailscale is unaffected regardless.
- **Dynamic public IP changes**: the residential IP can change at any time; on the
  direct path DDNS MUST update `vpn.ragnaforge.xyz` so client configs keep working,
  and on the fallback path the relay's stable IP absorbs the change — clients never
  re-import a config.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The edge MUST route inbound web requests to the correct deployed
  stack based on the request's hostname under `ragnaforge.xyz`.
- **FR-002**: A stack MUST become routable by declaring routing metadata on its own
  Compose definition (labels), with no edit to the edge's own configuration
  required to add, change, or remove a route.
- **FR-003**: The edge MUST serve every `*.ragnaforge.xyz` name over HTTPS using a
  certificate that mainstream browsers trust by default.
- **FR-004**: The edge MUST redirect plain-HTTP requests for `*.ragnaforge.xyz` to
  their HTTPS equivalent.
- **FR-005**: The system MUST obtain a wildcard certificate for `*.ragnaforge.xyz`
  from a public certificate authority automatically, proving domain control via a
  DNS-based challenge (so no inbound port is required for issuance).
- **FR-006**: The system MUST renew the certificate automatically before expiry
  with no operator action and no user-visible interruption.
- **FR-007**: The system MUST persist the issued certificate across edge restarts
  and reuse it rather than re-requesting on every start, to stay within the
  certificate authority's rate limits.
- **FR-008**: The system MUST provide an internal DNS resolver that answers
  `*.ragnaforge.xyz` with the edge host's LAN address (`10.0.0.70`) for **every**
  client — the same answer on LAN and on both VPN paths (no split-horizon) — while
  forwarding all other domains to upstream resolution.
- **FR-009**: The internal resolver MUST be usable by VPN clients such that
  `ragnaforge.xyz` names resolve to the edge for remote clients (i.e. not defeated
  by DNS-rebind protection).
- **FR-010**: The internal resolver MUST block a maintained list of ad/tracker
  domains network-wide, and this blocking MUST NOT break resolution of legitimate
  domains.
- **FR-011**: The system MUST keep the public `vpn.ragnaforge.xyz` DNS record
  pointed at the home's current public IP, updating it automatically when the IP
  changes.
- **FR-012**: The system MUST present a dashboard front door at
  `https://home.ragnaforge.xyz` that lists running apps with links to their HTTPS
  URLs.
- **FR-013**: All edge capabilities MUST be deployed through the existing Phase 2
  workflow — declared as stacks in git under the fleet definition and deployed from
  the control plane — not configured ad hoc on a node.
- **FR-014**: All credentials the edge needs (e.g. the DNS-provider API token) MUST
  come from the `mise`-rendered environment referenced by name in git, never as
  literal values in any tracked file; a missing required credential MUST cause a
  clear deploy/issuance failure rather than a silently-degraded edge.
- **FR-015**: **Exactly one** public port MUST be exposed to the internet — the
  secondary VPN's WireGuard port (UDP 51820), router-forwarded to the edge host.
  All other edge endpoints (apps, dashboard, resolver, and every admin UI) MUST NOT
  be directly reachable from the public internet; they are reachable only over the
  LAN or one of the two VPN paths.
- **FR-016**: Admin interfaces (resolver admin, dashboard config, proxy dashboard
  if any, and the secondary VPN's own admin UI) MUST be bound to LAN/Tailscale only
  and MUST NOT be reachable via the forwarded public port or any other public
  route.
- **FR-017**: The system MUST provide a **secondary remote-access VPN** (for
  family/friends) whose public endpoint is `vpn.ragnaforge.xyz` and whose only
  internet-facing surface is the single forwarded UDP port; a client with a valid
  config MUST be able to connect from off-LAN and reach the edge.
- **FR-018**: A connected secondary-VPN client MUST resolve `*.ragnaforge.xyz` to
  the edge and load apps over the same browser-trusted certificates as a LAN
  client; the VPN configuration MUST push the internal resolver to clients so those
  names resolve.
- **FR-019**: Both VPN paths MUST reach the edge: **Tailscale** as the operator
  path (no forwarded port) and the **secondary WireGuard VPN** as the family/friends
  path (the one forwarded port). Because the resolver returns the LAN address
  (`10.0.0.70`) to all clients, the edge host (Dell) MUST advertise/route the
  `10.0.0.0/24` subnet to **both** VPNs so a remote client is not stranded off
  `10.0.0.0/24`.
- **FR-020**: Generating/onboarding a secondary-VPN client config (a new
  family/friend) MUST NOT require exposing any additional port or hand-editing the
  edge; new clients are added through the VPN's managed workflow.
- **FR-021**: Before the secondary VPN is relied upon, the system MUST run a
  **preflight** that verifies the connection can host a public UDP endpoint —
  specifically: (a) the WAN address is a real public IPv4 and NOT a CGNAT/shared
  address, (b) UDP 51820 can be forwarded on the gateway and reached from an
  external network, and (c) `vpn.ragnaforge.xyz` resolves to that public IP. The
  preflight MUST yield an unambiguous GO (direct port-forward) / NO-GO (use
  fallback) result and MUST NOT report a false GO on inconclusive results.
- **FR-022**: If the preflight fails (CGNAT, port-forward blocked, or unstable), the
  system MUST provide a fallback that makes the secondary VPN reachable **without**
  a home inbound port — an always-on public relay (e.g. a small VPS) that forwards
  the WireGuard traffic to the edge host over an existing tunnel — such that remote
  clients still reach the edge and the client experience is unchanged.
- **FR-023**: Because the home's public IP is dynamic (residential Xfinity, no
  static IP), the public endpoint name `vpn.ragnaforge.xyz` MUST continue to resolve
  correctly across IP changes (via DDNS on the direct path, or the relay's stable IP
  on the fallback path), with no manual reconfiguration of client configs.

### Key Entities *(include if feature involves data)*

- **Edge host**: the node that terminates HTTPS and holds the certificate store and
  the internal resolver. On the LAN it is the address that `*.ragnaforge.xyz`
  resolves to (per PLAN.md, the Dell at `10.0.0.70`).
- **Route**: the association between a hostname (`<name>.ragnaforge.xyz`) and the
  container/port that serves it, declared as labels on a stack rather than in
  central proxy config.
- **Wildcard certificate**: a single Let's-Encrypt certificate for
  `*.ragnaforge.xyz` covering all current and future subdomains, with its private
  key and renewal state persisted on the edge host.
- **DNS zone `ragnaforge.xyz`**: the authoritative Cloudflare zone used for the
  DNS-01 challenge and for the public `vpn` record; and the **internal
  resolver's** view that overrides `*.ragnaforge.xyz` to the edge on the LAN.
- **DNS-provider credential**: the Cloudflare API token (a secret from `mise`) that
  authorizes both DNS-01 challenge records and DDNS updates.
- **App entry**: a listing on the Homepage dashboard pointing at a published app's
  HTTPS URL.
- **VPN path**: a way a client reaches the edge. Two exist — **Tailscale**
  (operator/admin, mesh, no forwarded port) and the **secondary WireGuard VPN**
  (family/friends, reached at `vpn.ragnaforge.xyz` via the one forwarded UDP port).
- **Secondary-VPN client**: a family/friend device holding a WireGuard config
  (endpoint `vpn.ragnaforge.xyz:51820`) that, once connected, is pushed the internal
  resolver and routed to the LAN subnet so it reaches the edge.
- **Exposed port**: the single internet-facing surface — UDP 51820, either forwarded
  by the xFi gateway to the edge host (direct path) or terminated on the cloud relay
  (fallback path). The one and only public entry point in this phase.
- **Preflight result**: the GO/NO-GO outcome of the connectivity checks (real public
  IP vs. CGNAT, port-forward reachable, DDNS resolving) that selects the direct
  port-forward path or the cloud-relay fallback.
- **Cloud relay (conditional)**: a small always-on VPS with a stable public IP,
  built only if the preflight fails, that receives WireGuard traffic on the public
  UDP port and tunnels it to the Dell over an existing tunnel.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A LAN user can open `https://home.ragnaforge.xyz` and it loads with a
  browser-trusted certificate and no security warning. *(Phase deliverable.)*
- **SC-002**: A stack deployed with routing labels through the Phase 2 workflow is
  reachable at its `https://<name>.ragnaforge.xyz` URL within 30 seconds of a
  successful deploy, without any edit to the edge's own configuration.
- **SC-003**: Publishing a brand-new subdomain requires zero certificate work — the
  new name is served under the existing wildcard certificate with no new issuance
  step and no per-app certificate.
- **SC-004**: The served certificate is issued by a public CA, valid for
  `*.ragnaforge.xyz`, and renews automatically; a simulated near-expiry results in
  an unattended renewal with no user-visible downtime.
- **SC-005**: From a device using the internal resolver, every `*.ragnaforge.xyz`
  name resolves to the edge host's LAN address, ordinary public domains still
  resolve, and at least one known ad/tracker domain is blocked.
- **SC-006**: All `http://<name>.ragnaforge.xyz` requests are redirected to
  `https://`; a request for an unclaimed hostname returns a clear not-found rather
  than a wrong app.
- **SC-007**: Restarting the edge does not trigger a new certificate request — the
  persisted certificate is reused (verified across at least one restart).
- **SC-008**: When the public IP changes, `vpn.ragnaforge.xyz` reflects the new
  address within the updater's configured interval.
- **SC-009**: No real secret value (notably the DNS-provider token) appears in any
  tracked file, and every edge capability is deployable from the control plane by a
  fresh clone plus a filled `.mise.toml` — nothing hand-configured on a node.
- **SC-010**: A port scan of the home's public IP shows **exactly one** open port
  (UDP 51820); no app, dashboard, resolver, or admin UI is directly reachable from
  the public internet (verified from an off-LAN, non-VPN vantage).
- **SC-011**: A remote device off the LAN and off Tailscale, using a fresh
  WireGuard config pointed at `vpn.ragnaforge.xyz`, connects and loads at least one
  `https://<name>.ragnaforge.xyz` app over a browser-trusted certificate.
- **SC-012**: The same `*.ragnaforge.xyz` app is reachable over **both** VPN paths
  (Tailscale and the secondary WireGuard VPN), each resolving the name to the edge
  and serving the trusted certificate.
- **SC-013**: The preflight runs **before** the secondary VPN is built and returns a
  clear GO/NO-GO: it correctly identifies whether the WAN IP is a real public
  address (not CGNAT) and whether an external probe reaches a test-forwarded UDP
  51820 — with no false GO on an inconclusive result.
- **SC-014**: The secondary VPN is reachable from off-LAN regardless of the
  preflight outcome — via the direct xFi port-forward when preflight passes, or via
  the cloud-relay fallback when it fails — and the family/friend client config and
  experience are identical in both cases.

## Assumptions

- **Domain & DNS provider**: `ragnaforge.xyz` is registered at **Porkbun** with its
  authoritative DNS delegated to **Cloudflare** (the registrar is not involved at
  runtime). A scoped Cloudflare API token (DNS edit for the zone) is available for
  both the DNS-01 challenge and DDNS.
- **Certificate authority**: Let's Encrypt is the CA; its production rate limits
  apply, which is why certificate persistence (FR-007) matters.
- **Edge placement**: the edge (reverse proxy + certificate store), the internal
  resolver, and the secondary VPN are **pinned to the Dell** (`10.0.0.70`), the
  always-on stateful node, per the project's "stateful → Dell" rule. The one public
  port forwards to the Dell and the resolver returns the Dell's IP, so the edge is a
  single-node, single-front-door on the Dell by design.
- **Deployment path**: every capability here is a Komodo-managed stack declared in
  git and deployed from Core (Phase 2 workflow); secrets come from `mise`. No new
  orchestration mechanism is introduced.
- **Scope boundary**: this phase delivers the edge, DNS/TLS plumbing, **and the
  secondary remote-access VPN** (pulled in per the Session 2026-07-19
  clarification). End-user applications (media, photos, budgeting, etc.) remain out
  of scope and are handled in later phases; the phase is validated with a trivial
  test stack (e.g. `whoami`) plus the Homepage dashboard, reached over the LAN and
  both VPN paths.
- **Two VPNs, distinct roles**: **Tailscale** = operator/admin path (already live
  from Phase 1, no forwarded port); **WireGuard / wg-easy** = family/friends path
  (new here, the single forwarded port). The two are complementary, not redundant.
- **Router & inbound IP (Xfinity)**: the home runs a **basic Xfinity gateway** with
  a **dynamic** residential IP (no static IP available) and the possibility of CGNAT
  or flaky xFi port-forwarding. The design does **not** assume inbound works — a
  preflight (US7 / FR-021) verifies it, and a cloud-relay fallback (FR-022) covers
  the case where it doesn't. Xfinity's default LAN (`10.0.0.1/24`) already matches
  the assumed `10.0.0.0/24`. Tailscale needs no inbound and is unaffected.
- **Cloud-relay fallback (conditional)**: only stood up if the preflight fails; a
  small always-on VPS with a stable public IP relays the WireGuard UDP to the Dell
  over an existing tunnel. It costs a few dollars a month and is the sole component
  that may or may not be built depending on the preflight result.
- **Subnet routing**: the resolver returns one address (`10.0.0.70`) to all
  clients, so the edge host (Dell) advertises/routes the `10.0.0.0/24` LAN subnet to
  **both** VPNs, letting remote clients reach LAN-addressed edge services (no
  split-horizon DNS).
- **Router/DHCP**: handing the internal resolver to LAN clients (via DHCP or manual
  configuration) is available to the operator; VPN clients are pushed the resolver
  via their VPN config. Making it the network-wide default resolver is desirable but
  the phase is provable by pointing a single test device at it.
- **Single front door accepted**: routing all apps through one edge host is a
  deliberate simplicity trade-off; if that host is down, the friendly URLs are down
  — acceptable for a home lab and revisited only if it becomes a pain point.
- **Reference tooling** (from PLAN.md, decided, not re-litigated here): Traefik
  (routing), Let's Encrypt via Cloudflare DNS-01 (TLS), AdGuard Home (internal
  resolver + ad-blocking), Cloudflare DDNS (dynamic record), Homepage (dashboard),
  and **wg-easy** (secondary WireGuard VPN, pulled forward from PLAN.md Phase 7).
  The conditional cloud-relay fallback (only if preflight fails) is a small VPS
  running WireGuard; specific provider is a planning detail.
