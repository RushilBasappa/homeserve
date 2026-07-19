# Quickstart — Validate Phase 3 (Edge, DNS & TLS)

Behavioral validation that the edge works end-to-end. Each scenario maps to Success
Criteria (SC-xxx) and a user story. This is a **run/validation guide** — the actual
compose files, labels, and scripts are produced in `/speckit-tasks` + implementation;
routing/TLS/DNS/VPN details live in the contracts and `research.md`.

## Prerequisites

- Phases 1–2 live: both nodes provisioned, Komodo Core + Periphery up, deploy-from-Core
  working (the `whoami` proof).
- `.mise.toml` filled (gitignored): `CLOUDFLARE_API_TOKEN` (DNS-edit on
  `ragnaforge.xyz`), plus the new `WG_EASY_PASSWORD_HASH`, `ADGUARD_ADMIN_PASSWORD`.
- Cloudflare is authoritative DNS for `ragnaforge.xyz` (registrar Porkbun; NS →
  Cloudflare). A `vpn.ragnaforge.xyz` A record exists (any value — DDNS corrects it).
- Dell prep: `:53` freed from `systemd-resolved`; `net.ipv4.ip_forward=1`; the external
  `traefik` Docker network created (`make edge-network`).

## Bring-up order

Deploy each edge stack from Komodo Core (declared in `komodo/stacks.toml`, targeting
`ragnaforge-dell`), in the order below — each provable before the next depends on it
(research R11).

---

### Scenario 0 — Preflight FIRST (US7 → SC-013)

Run **before** building the VPN:

```sh
make preflight        # scripts/preflight-public-endpoint.sh
```

**Expect**: a clear **GO** or **NO-GO** with a reason — checks public IP vs CGNAT
(`100.64.0.0/10`), external UDP-51820 reachability, and `vpn.ragnaforge.xyz`
resolution. An inconclusive result reports **NO-GO** (never a false GO). Record the
verdict; it selects Scenario 8's **direct** vs **relay** path.

### Scenario 1 — Wildcard cert issues unattended (US3 → SC-001/004/007)

Deploy `traefik` (fresh `traefik-acme` volume).

**Expect**: within a couple of minutes Traefik obtains a **Let's Encrypt**
`*.ragnaforge.xyz` cert via Cloudflare DNS-01 (watch logs / inspect `acme.json`
exists, `0600`). Restart the stack → **no** new issuance (cert reused). With a
bad/absent token, issuance fails **loudly** and no self-signed cert is served.

### Scenario 2 — Names resolve to the edge, ads blocked (US4 → SC-005)

Deploy `adguard`; point a test device's DNS at `10.0.0.70`.

**Expect**: `nslookup home.ragnaforge.xyz 10.0.0.70` → `10.0.0.70`; any
`<x>.ragnaforge.xyz` → `10.0.0.70`; a normal public domain still resolves; a known
ad/tracker domain is **blocked**. Same answer regardless of client (no split-horizon).

### Scenario 3 — App reachable at a friendly HTTPS name (US1/US2 → SC-001/002/003/006)

Add the canonical Traefik labels to `stacks/whoami` and deploy via Komodo.

**Expect**:
- `https://whoami.ragnaforge.xyz` loads with a **browser-trusted** cert, **no**
  warning, within ~30 s of deploy — no Traefik config edit. (SC-002)
- The new subdomain is covered by the **existing** wildcard (no new issuance). (SC-003)
- `http://whoami.ragnaforge.xyz` redirects to `https://`. (SC-006)
- `https://nope.ragnaforge.xyz` (unclaimed) → clear 404, not a wrong app. (SC-006)
- Stop the stack → the route stops responding (no stale route).

### Scenario 4 — Front door lists apps (US5 → SC-001)

Deploy `homepage`.

**Expect**: `https://home.ragnaforge.xyz` loads over trusted HTTPS and shows a working
link to `whoami` (and any other deployed app).

### Scenario 5 — DDNS tracks the public IP (US6 → SC-008)

Deploy `cloudflare-ddns`.

**Expect**: `vpn.ragnaforge.xyz` (Cloudflare) is set to the current public IP within
the configured interval; an unchanged IP triggers no needless update.

### Scenario 6 — Remote access over the secondary VPN (US8 → SC-011/012)

Per Scenario 0's verdict: **GO** → forward UDP 51820 on the xFi gateway and deploy
`wg-easy`; **NO-GO** → stand up the relay (`relay/README.md`), point `vpn` at the VPS,
then deploy `wg-easy`. Create a client config in the wg-easy admin (LAN/Tailscale
only). From a device **off-LAN and off-Tailscale** (e.g. phone hotspot), import the
`.conf` and connect.

**Expect**: tunnel establishes via `vpn.ragnaforge.xyz`; `https://whoami.ragnaforge.xyz`
(and `home.…`) loads over a **trusted** cert — identical whether direct or relayed.
Then confirm the **same** app also loads over **Tailscale** (SC-012).

### Scenario 7 — Only one port is public (US8 → SC-010)

From an external vantage, port-scan the home's public IP.

**Expect**: **only UDP 51820** responds. No app, dashboard, resolver, Traefik
dashboard, or admin UI (wg-easy `51821`) is reachable from off-LAN/off-Tailscale.

### Scenario 8 — Secret-free tree (SC-009)

```sh
grep -rnE 'changeme-|[A-Za-z0-9_-]{32,}' \
  komodo/ stacks/ --include=*.yaml --include=*.toml
git grep -nI "$CLOUDFLARE_API_TOKEN"    # must find nothing
```

**Expect**: no real secret value in any tracked file — only `${VAR}` / `[[VAR]]`
references. A fresh clone + filled `.mise.toml` reproduces the whole edge from Core.

---

## Done when

All scenarios pass: preflight gives a clear verdict; the wildcard cert is trusted and
persists; a labelled stack is reachable by HTTPS name within 30 s; names resolve to
`10.0.0.70` with ads blocked; the dashboard lists apps; DDNS tracks the IP; a remote
device reaches an app over **both** VPN paths; a public scan shows **only** UDP 51820;
and the tree is secret-free. Update the README Phase-3 section and the
`docs/runbooks/phase3-edge.md` runbook.
