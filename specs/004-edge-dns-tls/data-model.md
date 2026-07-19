# Phase 1 — Data Model: Edge, DNS & TLS

This phase has no application database. The "entities" are the **edge components,
their persisted state, and the declarations that wire them together** — the things a
reproducer must get right. Each lists its required content, where its state lives, and
the requirements/research it satisfies. Names follow `docs/CONVENTIONS.md` (stack =
directory = subdomain = Homepage entry; volumes `<app>-<purpose>`; all state on the
Dell).

---

## 1. Edge proxy — `traefik` (R1, R2)

- **Role**: terminates HTTPS on `:443`, Host-routes `<app>.ragnaforge.xyz` to the
  right container by label, redirects `:80`→`:443` globally.
- **Config**: static config (entryPoints `web`/`websecure`, the Docker provider, the
  Cloudflare DNS-01 `certificatesResolver`) via `traefik.yaml` or CLI args; optional
  dynamic config for the global redirect + TLS options.
- **State**: `traefik-acme` volume on the Dell holding `acme.json` (0600) — the
  wildcard cert + private key + renewal metadata.
- **Ports**: `80`, `443` (LAN/VPN — the front door). No admin dashboard exposed
  publicly; if enabled, LAN/Tailscale-only.
- **Network**: attached to the external `traefik` network (R10).
- **Secrets**: `CF_DNS_API_TOKEN=${CLOUDFLARE_API_TOKEN}` (R12).
- **Satisfies**: FR-001, FR-003, FR-004, US1/US2.

## 2. Wildcard certificate — `*.ragnaforge.xyz` (R2)

- **Role**: the single browser-trusted cert every subdomain reuses.
- **Content**: issuer = Let's Encrypt; `main = ragnaforge.xyz`, `sans =
  *.ragnaforge.xyz`; obtained via ACME **DNS-01** (Cloudflare).
- **State**: inside `acme.json` on `traefik-acme` (persisted → reused across restarts,
  auto-renewed lifetime-agnostically).
- **Validation**: served cert is LE-issued, valid for `*.ragnaforge.xyz`, browser
  trusts it; a restart does **not** trigger re-issuance.
- **Satisfies**: FR-003, FR-005, FR-006, FR-007; SC-001, SC-003, SC-004, SC-007.

## 3. Route (per app) — Traefik labels (R1)

- **Role**: the hostname→container binding, declared on the **app's** compose service,
  not in central proxy config.
- **Required labels** (canonical set from CONVENTIONS): `traefik.enable=true`;
  `routers.<app>.rule=Host(\`<app>.ragnaforge.xyz\`)`;
  `routers.<app>.entrypoints=websecure`; `routers.<app>.tls=true`;
  `services.<app>.loadbalancer.server.port=<container-port>`. Router/service name =
  stack name; `<container-port>` is the app's **internal** port.
- **Lifecycle**: appears when the labelled stack deploys; disappears when it stops (no
  stale route). Duplicate Host across two stacks = conflict to flag (edge case).
- **Satisfies**: FR-001, FR-002; SC-002, SC-006. Full contract:
  [`contracts/edge-routing-contract.md`](./contracts/edge-routing-contract.md).

## 4. Internal resolver — `adguard` (R3, R9)

- **Role**: LAN/VPN DNS. Answers `*.ragnaforge.xyz` → `10.0.0.70` **to every client**
  (no split-horizon); forwards all else upstream; blocks ad/tracker domains.
- **Config**: DNS **rewrite** rule `*.ragnaforge.xyz → 10.0.0.70`; upstream resolvers
  (Quad9/Cloudflare, DNSSEC on); enabled blocklists.
- **State**: `adguard-conf` + `adguard-work` volumes on the Dell.
- **Ports**: `53/tcp`+`53/udp` (LAN). Admin UI `:3000`/`:80`→bound LAN/Tailscale-only.
- **Pre-req**: `:53` freed from `systemd-resolved` on the Dell (R3 bring-up note).
- **Satisfies**: FR-008, FR-009, FR-010; SC-005. Contract:
  [`contracts/dns-resolution-contract.md`](./contracts/dns-resolution-contract.md).

## 5. Dynamic DNS updater — `cloudflare-ddns` (R4)

- **Role**: keep the public **A record `vpn.ragnaforge.xyz`** on the home's current
  IP; `PROXIED=false`.
- **Config**: token `${CLOUDFLARE_API_TOKEN}`, `DOMAINS=vpn.ragnaforge.xyz`, interval.
- **State**: none (stateless).
- **Satisfies**: FR-011, FR-023; SC-008. (On the relay path (R8) this is unnecessary —
  the VPS IP is static.)

## 6. Dashboard — `homepage` (R5)

- **Role**: front door at `home.ragnaforge.xyz` listing apps with HTTPS links.
- **Config**: `homepage/config/*.yaml` (settings, services/bookmarks); optional Docker
  label discovery.
- **State**: `homepage-config` volume on the Dell.
- **Route**: standard Traefik labels for `home.ragnaforge.xyz`.
- **Satisfies**: FR-012; SC-001, US5.

## 7. Secondary VPN — `wg-easy` (R6, R9)

- **Role**: family/friends WireGuard access; the **only** public exposure.
- **Config**: `WG_HOST=vpn.ragnaforge.xyz`; `WG_DEFAULT_DNS=10.0.0.70`;
  `WG_ALLOWED_IPS` incl. `10.0.0.0/24`; admin `PASSWORD_HASH=${WG_EASY_PASSWORD_HASH}`.
- **State**: `wg-easy-config` volume on the Dell (server + client keys).
- **Ports**: **`51820/udp` published + router-forwarded** (the one exposed port);
  admin `51821/tcp` bound **LAN/Tailscale-only** (never forwarded).
- **Host pre-req**: `net.ipv4.ip_forward=1` on the Dell; wg-easy manages NAT.
- **Satisfies**: FR-015, FR-016, FR-017, FR-018, FR-020; SC-010, SC-011, SC-012, US8.
  Contract: [`contracts/remote-access-contract.md`](./contracts/remote-access-contract.md).

## 8. Preflight result (R7)

- **Role**: the GO/NO-GO that selects direct-forward vs. relay, produced **before** the
  VPN is relied on.
- **Content**: checks — (a) public IPv4 not CGNAT (`100.64.0.0/10`), (b) external UDP
  51820 reachable, (c) `vpn.ragnaforge.xyz` resolves to that IP → single verdict, with
  reason. Inconclusive ⇒ NO-GO (never a false GO).
- **Producer**: `scripts/preflight-public-endpoint.sh` (`make preflight`).
- **Satisfies**: FR-021; SC-013, US7.

## 9. Cloud relay — conditional (R8)

- **Role**: built **only on NO-GO** — a public-IP VPS DNAT'ing `51820/udp` to the
  Dell's Tailscale IP so remote clients reach wg-easy without a home inbound port.
- **Content**: VPS on the tailnet; nftables/socat DNAT rule; `vpn.ragnaforge.xyz` → VPS
  static IP (DDNS not needed on this path). Recipe in `relay/README.md`.
- **Satisfies**: FR-022; SC-014.

## 10. Shared network — external `traefik` (R10)

- **Role**: the L2 the proxy and every HTTP app share; created once on the Dell.
- **Content**: `docker network create traefik` (external; apps reference it as
  `external: true`). Created by a bring-up step / `make edge-network`.
- **Satisfies**: FR-001 (routing substrate), FR-013.

## 11. Komodo declarations & variables (R10, R12)

- **`komodo/stacks.toml`**: one `[[stack]]` per edge stack (traefik, adguard,
  cloudflare-ddns, homepage, wg-easy) → `server = "ragnaforge-dell"`, `file_paths` →
  `stacks/<app>/compose.yaml`, `webhook_enabled = false` (manual deploy).
- **`komodo/variables.toml`**: non-secret `[[variable]]`s (e.g.
  `VPN_HOSTNAME=vpn.ragnaforge.xyz`); `FLEET_DOMAIN`, `DELL_LAN_IP` already exist.
- **Satisfies**: FR-013 (git source of truth, deploy from Core).

## 12. Secrets (git-safe references only) (R12)

| Secret (`${VAR}`) | Used by | Notes |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` | traefik (DNS-01), cloudflare-ddns | **exists**; DNS-edit scope on the zone |
| `WG_EASY_PASSWORD_HASH` | wg-easy admin | **new** placeholder; bcrypt hash |
| `ADGUARD_ADMIN_PASSWORD` | adguard admin | **new** placeholder (or set first-run + document) |

- **Rule**: real values only in the gitignored `.mise.toml`; tracked files carry
  `${VAR}` / `[[VAR]]` refs, never values (FR-014; SC-009).
