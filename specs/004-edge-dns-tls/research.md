# Phase 0 — Research: Edge, DNS & TLS

Decisions that resolve the plan's Technical Context. Each is
**Decision / Rationale / Alternatives**. IDs (R1…) are referenced from `plan.md`,
`data-model.md`, the contracts, `tasks.md`, and stack comments.

Ground rules carried in from the spec's Session 2026-07-19 clarifications: Let's
Encrypt via ACME DNS-01, lifetime-agnostic renewal (R2); exactly one exposed port
(R6); single-address DNS `10.0.0.70`, no split-horizon (R3); registrar Porkbun / DNS
Cloudflare (R2); everything pinned to the Dell (R10); Xfinity handled by a preflight
gate + relay fallback (R7, R8).

---

## R1 — Reverse proxy: Traefik v3, Docker-label discovery

**Decision**: **Traefik v3**, using the Docker provider to discover routes from
service **labels** on a shared external network named `traefik`. A single global
`web`→`websecure` HTTP→HTTPS redirect (entryPoint redirection). Router/service names
match the stack name. Exactly the label set already codified in
`docs/CONVENTIONS.md` ("Traefik routing labels").

**Rationale**: Label discovery is the whole point of FR-002/US2 — a new app becomes
routable by adding labels, no central proxy edit. Traefik's native Docker provider +
built-in ACME make it the lowest-custom-code option and it is the tool the
conventions doc already assumes. HTTP→HTTPS is configured once on the entryPoint, not
per app (FR-004).

**Alternatives**: **Caddy** (excellent auto-HTTPS, but label discovery is
add-on/less native and the repo already standardized on Traefik); **Nginx Proxy
Manager** (stateful DB, click-config — violates git-source-of-truth);
**hand-written Nginx** (per-app config edits — exactly what FR-002 forbids).

---

## R2 — TLS: Let's Encrypt wildcard via Cloudflare DNS-01, lifetime-agnostic

**Decision**: One **wildcard** `*.ragnaforge.xyz` certificate from **Let's Encrypt**,
obtained by Traefik's ACME **DNS-01** challenge against **Cloudflare**
(`CF_DNS_API_TOKEN` = the existing `CLOUDFLARE_API_TOKEN`). Configure a single
`certificatesResolvers` with `dnsChallenge.provider=cloudflare`; declare the wildcard
(`main: ragnaforge.xyz`, `sans: *.ragnaforge.xyz`) so one cert covers the apex
front-door names and every subdomain. Persist `acme.json` (0600) on the Dell volume
`traefik-acme`. **Do not** hardcode a lifetime or pin a profile — rely on Traefik's
automatic renewal (it renews well before expiry). Registrar is **Porkbun**; only
matters that the zone's nameservers are **Cloudflare** (they are), since DNS-01 edits
`_acme-challenge` TXT records in the Cloudflare zone.

**Rationale**: DNS-01 needs **no inbound port** (works before the VPN/preflight is
sorted) and is the only way to get a **wildcard**, which makes new subdomains
zero-issuance (FR-005, SC-003). Persisting `acme.json` avoids re-issuing on every
restart and staying within LE rate limits (FR-007, SC-007). Lifetime-agnostic
renewal absorbs LE's move to 45-day (2026-05-13) / 64-day (2027) certs with no rework
(spec clarification). ARI-driven renewal is a nice-to-have; Traefik's default renewal
window already covers every profile except opt-in 6-day, which we are not using.

**Alternatives**: **HTTP-01/TLS-ALPN-01** (needs inbound 80/443 and cannot issue
wildcards — rejected); **ZeroSSL / Google Trust Services** (peer ACME CAs, no benefit
over LE here — kept as a one-line `caServer` swap if ever needed); **per-app certs**
(defeats the zero-issuance goal); **opt-in 6-day short-lived** (needs flawless
2–3-day renewal — unnecessary blast-radius for a home lab).

---

## R3 — Internal DNS: AdGuard Home, single-address wildcard rewrite

**Decision**: **AdGuard Home** on the Dell as the LAN resolver. A **DNS rewrite**
`*.ragnaforge.xyz → 10.0.0.70` returned **identically to every client** (LAN and both
VPNs — no split-horizon, per clarification). Upstream DNS to a public resolver
(Quad9 / Cloudflare) for everything else; DNSSEC on. Ad/tracker **blocklists** enabled
(AdGuard defaults + a couple of well-known lists). Binds `:53` (TCP+UDP) on the Dell;
the admin UI is LAN/Tailscale-only (not router-forwarded).

**Rationale**: A single rewrite answer means one cert target and one mental model for
LAN, Tailscale, and WireGuard clients; reachability of `10.0.0.70` from off-LAN is
solved by subnet routing (R9, R6), not by DNS trickery (FR-008/009). AdGuard's
wildcard rewrites and blocklists are exactly FR-008/010 with ad-blocking as the free
bonus. **Bring-up note**: Debian's `systemd-resolved` holds `:53` via its stub
listener on the Dell — free it (disable `DNSStubListener`, or bind AdGuard to the LAN
IP) before AdGuard can bind (provision task / runbook).

**Alternatives**: **Pi-hole** (equivalent; AdGuard has cleaner native wildcard
rewrites + built-in DoH/DoT upstream); **CoreDNS/dnsmasq** (more hand-config, no UI);
**Traefik/host-file hacks** (don't scale to VPN clients).

---

## R4 — Dynamic DNS: favonia/cloudflare-ddns → vpn.ragnaforge.xyz

**Decision**: A small **`favonia/cloudflare-ddns`** container updating the **A record
for `vpn.ragnaforge.xyz`** in the Cloudflare zone from the home's detected public IP,
on a short interval. Uses a Cloudflare token (reuse `CLOUDFLARE_API_TOKEN`, DNS-edit
scope on the zone). `PROXIED=false` (WireGuard UDP cannot go through Cloudflare's
proxy). Stateless — no volume.

**Rationale**: Residential Xfinity has a **dynamic** IP and no static option; the
secondary VPN's endpoint name must track it (FR-011, FR-023, SC-008). `favonia` is
maintained, minimal, token-scoped, and IPv6-aware. Only the `vpn` record is dynamic;
app names resolve internally via AdGuard, so no public app records are needed.

**Alternatives**: **oznu/cloudflare-ddns** (older, less maintained);
**ddclient** (heavier, perl); **Cloudflare Tunnel** (would also expose apps publicly
— out of scope this phase, and UDP/WireGuard isn't a fit).

---

## R5 — Dashboard: Homepage (gethomepage/homepage) at home.ragnaforge.xyz

**Decision**: **Homepage** as the front door at `home.ragnaforge.xyz`, Traefik-routed
like any app. Front-door entries defined in tracked config (`homepage/config/*.yaml`);
optional Docker-label service discovery for auto-listing. Bookmarks/links to each
app's HTTPS URL. Config volume on the Dell.

**Rationale**: FR-012/US5 want one memorable place listing apps; Homepage is
static-config, git-friendly, and integrates with Traefik/Docker for auto-discovery so
the list stays current with minimal upkeep. It is the phase's named deliverable URL.

**Alternatives**: **Heimdall** (DB-backed, click-config — off the git model);
**Dashy** (heavier build); a **hand-written index** (more custom code, no service
health widgets).

---

## R6 — Secondary VPN: wg-easy, exactly one exposed UDP port

**Decision**: **wg-easy** (`ghcr.io/wg-easy/wg-easy`) on the Dell. Publishes **only**
`51820/udp` (router-forwarded → the one public port); the admin UI (`51821/tcp`) binds
**LAN/Tailscale only**, never forwarded. `WG_HOST=vpn.ragnaforge.xyz`;
`WG_DEFAULT_DNS=10.0.0.70` (push AdGuard to clients so `*.ragnaforge.xyz` resolves);
`WG_ALLOWED_IPS` includes `10.0.0.0/24` so clients route the LAN subnet through the
tunnel to reach the Dell/edge. Admin password supplied as a **bcrypt hash**
(`PASSWORD_HASH`, from `${WG_EASY_PASSWORD_HASH}`). Client keys persisted on the Dell
volume `wg-easy-config`. Requires host IP forwarding + NAT (wg-easy sets its own
`iptables` MASQUERADE); enable `net.ipv4.ip_forward` on the Dell (Phase-1 sysctl or a
new task).

**Rationale**: wg-easy gives non-technical family/friends simple `.conf`/QR onboarding
(incl. Fire TV via file import) with one small admin UI — matching FR-017/020/US8 and
the "easy .conf" goal from clarification. Pushing DNS + AllowedIPs to clients is what
makes a remote device resolve and reach `10.0.0.70` exactly like a LAN device
(FR-018). One published UDP port satisfies the "exactly one exposed port" rule
(FR-015). The conventions doc already reserves `51820/udp → Dell` for wg-easy.

**Alternatives**: **Raw wg + manual configs** (no onboarding UI — worse for
family); **Tailscale for family too** (needs accounts/app install — rejected in
clarification, loses `.conf` simplicity); **OpenVPN** (heavier, slower, more config).

---

## R7 — Preflight gate (US7): checks-first, GO/NO-GO

**Decision**: A `scripts/preflight-public-endpoint.sh` (run via `make preflight`) that
runs **before** wg-easy is relied upon and prints an unambiguous **GO / NO-GO**:
1. **Public IP vs CGNAT** — fetch the external IP (e.g. `curl -s https://api.ipify.org`)
   and the gateway WAN IP; NO-GO if the external IP is in a CGNAT/shared range
   (`100.64.0.0/10`) or differs from a routable WAN IP (double-NAT/CGNAT signal).
2. **Port reachability** — with UDP 51820 temporarily forwarded, probe it from an
   **external** vantage (an outside host / phone hotspot, or an external port-check
   service) and confirm the WireGuard handshake/UDP response.
3. **DDNS** — confirm `vpn.ragnaforge.xyz` resolves to that public IP.
Inconclusive/intermittent ⇒ **NO-GO** (never a false GO). The result selects the
direct-forward path (R6) or the relay fallback (R8) and is recorded in the runbook.

**Rationale**: Xfinity residential *usually* gives a real dynamic public IP and the
xFi app can forward a port — but CGNAT/flaky-forward is increasingly possible, so the
spec makes this the **first step** (FR-021, SC-013). Cheap to run, saves building the
VPN against a dead path. CGNAT detection via the `100.64.0.0/10` range + external-IP
comparison is the standard, dependency-free check.

**Alternatives**: **Assume it works** (Option B, rejected in clarification — silent
late failure); **STUN-based NAT typing** (more moving parts than a home lab needs);
**skip and always relay** (R8 as default — unnecessary cost/complexity when direct
usually works).

---

## R8 — Cloud-relay fallback (conditional): VPS DNAT over Tailscale

**Decision**: **Only built on preflight NO-GO.** A small always-on **VPS** with a
stable public IP, joined to the **Tailscale** tailnet, that **DNATs** inbound public
`51820/udp` to the Dell's Tailscale IP (nftables/socat), so remote WireGuard clients
reach wg-easy on the Dell without any home inbound port. `vpn.ragnaforge.xyz` then
points at the **VPS** IP (static — DDNS not needed on this path). Client configs and
experience are identical to the direct path (FR-022, SC-014). Recipe lives in
`relay/README.md`; the VM itself is out-of-repo (a few $/mo).

**Rationale**: A public-IP relay is the standard CGNAT bypass and reuses Tailscale
(already deployed) as the secure home-ward transport — no new inbound at home, no new
trust anchor. Keeping it **conditional** honors "minimal moving parts" — it exists
only if R7 says it must.

**Alternatives**: **Cloudflare Tunnel** (TCP/HTTP-oriented; awkward for
WireGuard/UDP and would broaden exposure); **Tailscale Funnel** (HTTP(S) only —
not raw WireGuard); **ISP change / bridge mode / static IP** (documented as manual
remediation the operator may prefer to a VPS, but not something we can automate).

---

## R9 — Reaching 10.0.0.70 from VPN clients: subnet routing

**Decision**: Because AdGuard returns `10.0.0.70` to **all** clients (R3), each VPN
must carry clients to that address:
- **Tailscale (operator)** — the Dell advertises `--advertise-routes=10.0.0.0/24`,
  approved once in the Tailscale admin; operator devices `--accept-routes`.
- **WireGuard (family)** — wg-easy sets client `AllowedIPs` to include `10.0.0.0/24`
  and the Dell NATs tunnel traffic onto the LAN (R6). Since Traefik/AdGuard run **on**
  the Dell, reaching `10.0.0.70` itself is direct; the subnet route also lets clients
  reach any other LAN host if ever needed.

**Rationale**: This is the other half of the single-address decision (FR-009/019) —
one DNS answer only works if every path can actually route to it. Subnet routing is
the native, low-config mechanism in both VPNs.

**Alternatives**: **Split-horizon DNS** (rejected in clarification — fiddly, more
failure modes); **per-path hostnames** (breaks the one-cert/one-name model).

---

## R10 — Placement & networking: all edge on the Dell, one shared network

**Decision**: **Every** edge stack runs on the **Dell** (`ragnaforge-dell`), declared
in `komodo/stacks.toml` with `server = "ragnaforge-dell"`. A single **external**
Docker network **`traefik`** is created once on the Dell (`docker network create` via
`make edge-network` / bring-up step); Traefik and every HTTP app join it. AdGuard
(`:53`) and wg-easy (`51820/udp`) publish host ports; DDNS needs no port. HTTP apps
publish **no** host ports (reached only via Traefik, per conventions).

**Rationale**: The resolver answer (`10.0.0.70`), the one forwarded port, the cert
store, and the "stateful → Dell" rule all converge on the Dell — so the edge is a
single-node front door by design (spec: edge pinned to the Dell). One shared external
network is the standard Traefik pattern and keeps app composes to just labels +
`networks: [traefik]`.

**Alternatives**: **Spread edge across both nodes** (contradicts the single-address
decision and adds cross-node cert reachability — rejected); **Traefik per-app
networks** (more plumbing than a shared external net).

---

## R11 — Deployment path & bring-up order

**Decision**: All six stacks are **Komodo-managed** (declared in `komodo/`, deployed
from Core) — none is bootstrapped out-of-band (unlike Phase 2's control plane, which
already exists). Bring-up order (runbook `docs/runbooks/phase3-edge.md`):
1. Free `:53` on the Dell (R3) + enable IP forwarding (R6); create the `traefik`
   network (R10).
2. Deploy **Traefik** → confirm the wildcard cert issues (R2).
3. Deploy **AdGuard**, point a test device at it → names resolve to `10.0.0.70`.
4. Relabel + deploy **whoami** → `https://whoami.ragnaforge.xyz` loads (US1/US2).
5. Deploy **Homepage** (front door) and **Cloudflare-DDNS**.
6. Run **`make preflight`** (R7) → GO: forward UDP 51820 + deploy **wg-easy**;
   NO-GO: stand up the **relay** (R8) first, then wg-easy.

**Rationale**: Each layer is provable before the next depends on it; the VPN slice is
gated on the preflight exactly as the spec's "checks first" decision requires.

**Alternatives**: Deploy-all-then-debug (worse failure isolation); bootstrapping the
edge out-of-band (unnecessary — Core is up and the edge is normal workload).

---

## R12 — Secrets & variables

**Decision**: Reuse the existing **`CLOUDFLARE_API_TOKEN`** (already in
`.mise.toml.example`, scoped DNS-edit on the zone) for both Traefik DNS-01 and DDNS.
Add two placeholders to `.mise.toml.example`, referenced as `${VAR}` only:
- `WG_EASY_PASSWORD_HASH` — bcrypt hash of the wg-easy admin password (R6).
- `ADGUARD_ADMIN_PASSWORD` — AdGuard admin (bcrypt in AdGuard's config, or set on
  first run and documented).
Add non-secret git-declared **variables** to `komodo/variables.toml` as needed (e.g.
`VPN_HOSTNAME=vpn.ragnaforge.xyz`); `FLEET_DOMAIN` and `DELL_LAN_IP` already exist.

**Rationale**: Keeps the tree secret-free (FR-014) and reuses the one Cloudflare token
already provisioned. Non-secret hostnames/IPs live in `variables.toml` as `[[VAR]]`;
real secrets stay in the gitignored `.mise.toml` as `${VAR}`.

**Alternatives**: **Separate DDNS-only token** (marginally tighter scope — optional
hardening, noted but not required); **committing config with values** (forbidden).
