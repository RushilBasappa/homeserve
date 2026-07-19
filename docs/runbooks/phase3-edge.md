# Runbook — Phase 3: Edge, DNS & TLS

Bring up the edge: Traefik + a Let's Encrypt wildcard cert, AdGuard internal DNS,
Homepage, Cloudflare DDNS, and the wg-easy family/friends VPN — every capability a
Komodo-managed stack on the Dell, deployed from Core. This runbook is the
operator's bring-up order and the validation each layer must pass before the next
depends on it (research R11; quickstart Scenarios 0–8).

> **One-line flow:** resolver (`*.ragnaforge.xyz → 10.0.0.70`) → subnet route →
> Traefik Host-routing → shared wildcard cert.

## Prerequisites

- Phases 1–2 live: both nodes provisioned, Komodo Core + Periphery up,
  deploy-from-Core proven.
- `.mise.toml` filled (gitignored) with `CLOUDFLARE_API_TOKEN` (DNS-edit on the
  `ragnaforge.xyz` zone), plus the new `WG_EASY_PASSWORD_HASH` (bcrypt) and
  `ADGUARD_ADMIN_PASSWORD`. After editing, `make sync-secrets`.
- Cloudflare is authoritative DNS for `ragnaforge.xyz` (registrar Porkbun; NS →
  Cloudflare). A `vpn.ragnaforge.xyz` A record exists (any value — DDNS corrects).
- Generate the wg-easy admin hash:
  `docker run --rm ghcr.io/wg-easy/wg-easy wgpw 'your-admin-password'` → paste the
  hash into `.mise.toml` as `WG_EASY_PASSWORD_HASH`.

## 0. Dell host prep (Foundational — before any stack)

Run the Phase-3 provision additions (idempotent), then create the shared network:

```sh
make provision-dell        # edge-dns.yml frees :53; sysctl.yml ensures ip_forward=1
# on the Dell:
make edge-network          # create the external `traefik` Docker network (idempotent)
```

What this does:
- **`:53` free for AdGuard** — on this fleet `:53` is already free (no
  `systemd-resolved`; Tailscale's resolver is at `100.100.100.100`), so
  `provision/tasks/edge-dns.yml` just asserts it. ⚠️ Do **not** repoint
  `/etc/resolv.conf` — **Tailscale owns it** (MagicDNS). A dangling
  `/run/systemd/resolve/...` symlink on a host without resolved breaks all DNS
  (this bit us once during bring-up).
- **IP forwarding** — `net.ipv4.ip_forward=1` persisted for wg-easy NAT
  (`provision/tasks/sysctl.yml`).
- **`traefik` network** — the L2 Traefik and every HTTP app share (research R10).

> **Secret plumbing:** every stack secret referenced as `${VAR}` must be forwarded
> in `komodo/bootstrap/periphery.compose.yaml`'s `environment:` (that is how it
> reaches the Periphery-run `docker compose`), then `make sync-secrets` +
> **recreate Periphery** so the new env takes effect. Non-secret config
> (hostnames/IPs) is **inlined as a literal** in the stack compose — Komodo does
> NOT interpolate `[[VAR]]` into git-pulled compose content here (confirmed: the
> DDNS deploy got the literal `[[VPN_HOSTNAME]]`). Forgetting the forward =
> `${VAR}` resolves empty at deploy.

**Checkpoint:** `traefik` network exists; `sudo ss -lunp | grep :53` shows nothing
bound; `sysctl net.ipv4.ip_forward` = 1.

## Deploying edge stacks from Komodo (read once)

Each edge stack is deployed from Komodo Core (git source of truth). Bring-up
findings (2026-07-19), so future deploys are smooth:

- **Core polls git every 5 min** (`KOMODO_RESOURCE_POLL_INTERVAL=5-min` in
  `core.env`; Komodo's default was 1-hr, which served stale commits long after a
  push). So after `git push`, wait ≤5 min and Core's view is current — a
  `DeployStack` then uses the latest code. To pick up a push immediately, run the
  `homeserve` ResourceSync (Komodo UI → Syncs → Execute, or API `RunSync`), which
  reconciles `komodo/stacks.toml` and refreshes the clone. RunSync is required
  when `stacks.toml` itself changed (new/removed/retargeted stack); a plain code
  change to an existing stack just needs Deploy. Polling refreshes the VIEW only —
  deploys stay deliberate (each stack `webhook_enabled=false`).
- **Secrets must be forwarded** in `komodo/bootstrap/periphery.compose.yaml`'s
  `environment:` (see that file), then `make sync-secrets` **and recreate
  Periphery** (`mise exec -- docker compose -f komodo/bootstrap/periphery.compose.yaml up -d`)
  so the new env is live. `${VAR}` in a stack resolves from the Periphery agent env.
- **No host bind mounts for config** — Komodo's compose project dir doesn't
  resolve repo-relative paths; Docker then creates an empty dir. Ship config as
  CLI flags or an inline compose `configs: content:` block (see `stacks/traefik/`).

## 1. Traefik + wildcard cert (US3 → quickstart Scenario 1) ✅ done 2026-07-19

> **Delivered:** Traefik v3 deployed from Core; LE wildcard `*.ragnaforge.xyz`
> issued via Cloudflare DNS-01, persisted (acme.json 0600), reused on restart;
> `https://whoami.ragnaforge.xyz` trusted + 200; HTTP→HTTPS 301; unclaimed → 404.

Deploy `traefik` from Komodo Core (fresh `traefik-acme` volume).

**Expect:** within a couple of minutes Traefik obtains a **Let's Encrypt**
`*.ragnaforge.xyz` cert via Cloudflare DNS-01 (watch `docker logs traefik`;
confirm `acme.json` exists and is `0600` inside the `traefik-acme` volume).
Restart the stack → **no** re-issuance (cert reused; SC-007). A bad/absent
`CLOUDFLARE_API_TOKEN` must fail **loudly** — no self-signed cert served.

```sh
docker exec traefik ls -l /acme/acme.json      # -rw------- (0600)
```

**Checkpoint:** wildcard cert live and persisted; the proxy is ready to route.

## 2. AdGuard internal DNS (US4 → quickstart Scenario 2)

Deploy `adguard`, then complete the first-run config in
[`stacks/adguard/README.md`](../../stacks/adguard/README.md) (rewrite
`*.ragnaforge.xyz → 10.0.0.70`, upstreams + DNSSEC, blocklists, admin password).
Point a test device's DNS at `10.0.0.70`.

**Expect:** `nslookup home.ragnaforge.xyz 10.0.0.70 → 10.0.0.70`; any
`<x>.ragnaforge.xyz → 10.0.0.70`; a public domain still resolves; a known ad
domain is blocked. Same answer for every client (no split-horizon).

**Checkpoint:** friendly names resolve network-wide; ad-blocking active.

## 3. whoami — app reachable by HTTPS name (US1/US2 → Scenario 3)

`whoami` already carries the canonical Traefik labels and is pinned to the Dell in
`komodo/stacks.toml`. Redeploy it from Core.

**Expect:**
- `https://whoami.ragnaforge.xyz` loads with a **browser-trusted** cert, no
  warning, within ~30 s — no Traefik config edit (SC-002), served under the
  existing wildcard (SC-003).
- `http://whoami.ragnaforge.xyz` redirects to `https://` (SC-006).
- `https://nope.ragnaforge.xyz` → clear 404, not a wrong app (SC-006).
- Stop the stack → the route stops responding within seconds (no stale route).

Before AdGuard resolves it, test with a temporary hosts override
(`whoami.ragnaforge.xyz → 10.0.0.70`); remove it once Step 2 is live.

**Publish-by-labels proof (US2):** add a second router (e.g. a `whoami2` Host
rule) and confirm it is served under the **existing** wildcard with **no** Traefik
config edit and **no** new issuance; then revert.

## 4. Homepage front door (US5 → Scenario 4)

Deploy `homepage`.

**Expect:** `https://home.ragnaforge.xyz` loads over trusted HTTPS and shows a
working link to `whoami`.

## 5. Cloudflare DDNS (US6 → Scenario 5)

Deploy `cloudflare-ddns` (direct path only — skip on the relay path).

**Expect:** `vpn.ragnaforge.xyz` is set to the current public IP within ~5 min; an
unchanged IP triggers no needless update (SC-008).

## 6. Preflight — GO/NO-GO (US7 → Scenario 0, runs BEFORE wg-easy)

```sh
make preflight
# to complete the external UDP check, temporarily forward UDP 51820, then from an
# external vantage (phone hotspot / friend's box) confirm a WireGuard handshake and:
EXTERNAL_UDP_51820=open make preflight     # or =closed if unreachable
```

**Expect:** a clear **GO** or **NO-GO** with reasons — public IP vs CGNAT
(`100.64.0.0/10`), external UDP-51820 reachability, `vpn.ragnaforge.xyz`
resolution. Inconclusive ⇒ NO-GO (never a false GO).

**Verdict recorded (2026-07-19):**

| Field | Value |
|---|---|
| Date run | 2026-07-19 |
| Public IP | `76.102.108.83` |
| CGNAT? | **No** — routable public Xfinity address (not in `100.64.0.0/10`) |
| External UDP 51820 | pending — needs the xFi port-forward + an external probe |
| Verdict | **GO (direct path)** — the CGNAT gate passed; a home port-forward is feasible |
| Chosen path | **direct port-forward** (no VPS relay needed) |

The script printed a conservative NO-GO only because checks 2–3 weren't set up yet
(nothing forwarded; `vpn` still resolved to the Tailscale IP from the wildcard). Both
are pending setup, not failures. Path = **direct**: deploy DDNS (Step 5) → forward
UDP 51820 → re-run `EXTERNAL_UDP_51820=open make preflight` to confirm.

## 7. wg-easy — the secondary VPN (US8 → Scenarios 6 & 7)

Advertise the LAN subnet to Tailscale clients (operator path) first:

```sh
# on the Dell:
sudo tailscale up --advertise-routes=10.0.0.0/24
# then approve the route in the Tailscale admin console; operator devices --accept-routes
```

Then per the Step 6 verdict:

- **GO** → on the xFi gateway, forward **only** UDP 51820 → the Dell
  (`10.0.0.70`). Document the exact xFi app steps here as you do them.
- **NO-GO** → stand up the relay from [`relay/README.md`](../../relay/README.md)
  (VPS on the tailnet DNAT'ing `51820/udp` → the Dell's Tailscale IP) and point
  `vpn.ragnaforge.xyz` at the VPS static IP. Stop `cloudflare-ddns`.

Deploy `wg-easy` from Core; create a client config in the admin UI (`:51821`,
LAN/Tailscale only).

**Expect (Scenario 6):** from a device **off-LAN and off-Tailscale** (phone
hotspot), import the `.conf`, connect via `vpn.ragnaforge.xyz`, and load
`https://whoami.ragnaforge.xyz` + `https://home.ragnaforge.xyz` over trusted HTTPS
— identical whether direct or relayed. Confirm the same app also loads over
Tailscale (SC-012).

**Family/friend onboarding:** create one client per person in the wg-easy admin;
send the `.conf` (or QR). On a **Fire TV**, install the WireGuard app and import
the `.conf` via a file (USB / Send Files to TV) — QR scanning isn't available on
that remote.

**Expect (Scenario 7 — the exposure invariant):** port-scan the home's public IP
from an external vantage → **only UDP 51820** responds. No app, dashboard,
resolver, or admin UI (wg-easy `51821`, AdGuard `3000`, Traefik) is reachable
off-LAN/off-Tailscale (SC-010).

**Checkpoint:** private remote access works over both VPN paths; exactly one port
public.

## 8. Secret-free tree (SC-009)

```sh
grep -rnE 'changeme-|[A-Za-z0-9_-]{32,}' komodo/ stacks/ --include=*.yaml --include=*.toml
git grep -nI "$CLOUDFLARE_API_TOKEN"     # must find nothing
```

**Expect:** only `${VAR}` / `[[VAR]]` references in tracked files. A fresh clone +
filled `.mise.toml` reproduces the whole edge from Core.

## Ports opened this phase

| Port | Proto | Stack | Exposure |
|---|---|---|---|
| 80, 443 | TCP | traefik | LAN / VPN (443 is the front door) |
| 53 | TCP/UDP | adguard | LAN (internal DNS) |
| 3000 | TCP | adguard | LAN/Tailscale admin (never forwarded) |
| 51820 | UDP | wg-easy | **the one** router-forwarded / relayed public port |
| 51821 | TCP | wg-easy | LAN/Tailscale admin (never forwarded) |
