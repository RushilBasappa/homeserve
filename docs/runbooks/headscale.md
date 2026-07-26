# Runbook — Headscale (self-hosted Tailscale control plane)

**Feature**: `specs/011-headscale-vpn` · **Stack**: `stacks/headscale/` · **Node**: the Dell
(`ragnaforge-dell`) · **Replaces**: `wg-easy` (removed) + the owner's dependence on Tailscale's SaaS
control plane (Tailscale kept installed, stopped, as rollback).

Headscale is the fleet's **own** coordination server. Remote clients run the **standard Tailscale apps**
pointed at `https://headscale.ragnaforge.xyz` via `--login-server`. This is the **only** internet-facing
fleet service.

---

## 1. Ports & router forwarding (the public surface)

| Port | Proto | Where it goes | Purpose | Public? |
|------|-------|---------------|---------|---------|
| **443** | TCP | xFi → Traefik → `headscale:8080` | handshake, enroll/login, key & config validation, control stream, **embedded DERP relay** | **forward it** |
| **3478** | UDP | xFi → `headscale` container (bound `10.0.0.70`) | STUN — NAT traversal for **direct** P2P (blocked ⇒ all-relay, still works) | **forward it** |
| 80 | TCP | — | not needed (TLS via DNS-01 wildcard, not HTTP-01) | no |
| 41641 | UDP | — | optional; improves direct-link odds to home nodes | optional |
| ~~51820~~ | ~~UDP~~ | ~~wg-easy~~ | **remove this forward** when retiring wg-easy | removed |

**Posture note**: this is the **first** time `443/tcp` is router-forwarded (old design forwarded only
`51820/udp`). The public 443 surface is only the Headscale vhost behind a valid `*.ragnaforge.xyz` cert.
**Keep the Xfinity gateway on Typical Security** so nothing leaks on public IPv6; STUN is bound to
`10.0.0.70`, never `[::]` (see the ipv6-exposure note).

---

## 2. Deploy (order matters — validate BEFORE exposure)

1. **DNS**: confirm `cloudflare-ddns` publishes `headscale.ragnaforge.xyz` → home public IP
   (`DOMAINS` in `stacks/cloudflare-ddns/compose.yaml`, `PROXIED=false`).
2. **Pin check (T008)**: the compose pins `headscale/headscale:0.26.1`. **Avoid 0.27.0**
   (client-can't-connect regression, juanfont/headscale#2870). If you bump the tag, re-diff its
   `config-example.yaml` against the inline `config.yaml` for key drift.
3. **Deploy** the stack via Komodo (`DeployStack headscale`). The `WRN listening without TLS but
   ServerURL does not start with http://` log line is **expected/benign** — Traefik terminates TLS.
4. **Validate (T014, fail-closed)** — do this while up but **before** opening the router forward:
   ```sh
   docker exec headscale headscale configtest
   cd stacks/headscale/configure && mise exec -- ansible-playbook assert.yml
   ```
   Both must be green.
5. **Open the router forward (T015)**: `443/tcp` + `3478/udp` → `10.0.0.70`. Keep Typical Security.
6. **Subnet router (T016)** — join the Dell to its own tailnet advertising the LAN:
   ```sh
   sudo tailscale up --login-server https://headscale.ragnaforge.xyz --advertise-routes=10.0.0.0/24
   docker exec headscale headscale routes list      # confirm 10.0.0.0/24 auto-approved
   ```
   (Route auto-approval comes from `autoApprovers.routes` in the inline policy, tied to
   `tag:subnet-router`. Tag the Dell node if it isn't: `headscale nodes tag -i <id> -t tag:subnet-router`.)

> **Inline config = recreate on edit.** `config.yaml` and `policy.hujson` ship inline (`configs:`). Editing
> them needs a **container recreate** (DestroyStack + DeployStack), not just a redeploy.

---

## 3. Users, keys & guest onboarding

### Create users (once)
```sh
docker exec headscale headscale users create owner
docker exec headscale headscale users create guests
```
> **Policy identity form (verify here).** The inline `policy.hujson` references users as `owner@` /
> `guests@` (policy v2). If `headscale configtest` / `headscale policy check` rejects that form on your
> pinned tag, change the `groups`/`tagOwners` entries to the exact string `headscale users list` prints
> (often the bare name), then recreate the container.

### Enroll the OWNER
```sh
docker exec headscale headscale preauthkeys create --user owner --expiration 1h
# on the device:
sudo tailscale up --login-server https://headscale.ragnaforge.xyz --authkey <key>
```

### Onboard a GUEST (the "one paste" flow)
1. Owner mints a **single-use, time-boxed** key (CLI or the optional web UI, §5):
   ```sh
   docker exec headscale headscale preauthkeys create --user guests --expiration 24h
   # add --reusable ONLY for a shared family device
   ```
2. Guest installs the **Tailscale app** and points it at the custom server:
   - **Android / Windows / Linux / macOS (CLI)**:
     `tailscale login --login-server https://headscale.ragnaforge.xyz --authkey <key>`
   - **iOS / macOS (app)**: Tailscale → *Settings → Use custom coordination server* (a.k.a. alternate/
     custom login server) → enter `https://headscale.ragnaforge.xyz` → sign in / paste the key.
3. Guest opens a shared `*.ragnaforge.xyz` app — it loads over HTTPS, on cellular too.

**Key expiry / re-auth**: when a node key expires the guest just re-runs the login (or re-taps connect
with a fresh key). Revoke early with `headscale preauthkeys expire ...` or
`headscale nodes delete -i <id>`.

**Known gap**: there is no Fire-TV-class onboarding as clean as wg-easy's file import — TV devices need
the Tailscale app + custom-server support, which not all TV OSes expose. Out of scope for v1.

### What guests can and can't reach
The ACL scopes `guests` to `10.0.0.0/24:443` (the HTTPS front door) + DNS — so SSH, Komodo, NFS, and the
AdGuard admin are blocked. **Limit (by design):** network ACLs gate host:port, **not** vhost — a guest on
`:443` can, at the network layer, reach any vhost Traefik serves. True per-**app** scoping is each app's
own auth (the existing fleet model).

---

## 4. DNS & why friendly names still work

MagicDNS is **off**. The control server pushes **split DNS**: `ragnaforge.xyz → 10.0.0.70` (AdGuard)
only — clients keep their own resolver otherwise. Combined with the approved `10.0.0.0/24` route, a
remote device resolves `*.ragnaforge.xyz → 10.0.0.70` and reaches Traefik + the wildcard cert exactly
like on the LAN. `headscale.ragnaforge.xyz` itself resolves **publicly** via Cloudflare, so it's
reachable before the tunnel exists (no chicken-and-egg).

---

## 5. Optional web admin UI

`headscale-ui` (in the compose, `headscale-ui.ragnaforge.xyz`, **LAN/Tailscale-only, never forwarded**)
is a browser app for minting/expiring keys and viewing nodes without the CLI. It calls the Headscale API
from the browser: create a key and paste it in the UI:
```sh
docker exec headscale headscale apikeys create --expiration 90d
```
(Store it as `HEADSCALE_API_KEY` in `.mise.toml` for reference. Delete the `headscale-ui` service if you
prefer CLI-only.)

---

## 6. Backup & restore

All tailnet state (SQLite DB + `noise_private.key` + `derp_server_private.key`) lives on the
`headscale-data` volume. **Back it up = back up the whole tailnet.**
```sh
# backup
docker run --rm -v headscale-data:/d -v "$PWD":/b alpine tar czf /b/headscale-data.tgz -C /d .
# restore (into a fresh volume, then DeployStack)
docker run --rm -v headscale-data:/d -v "$PWD":/b alpine sh -c 'cd /d && tar xzf /b/headscale-data.tgz'
```
Reproducibility drill (SC-008): destroy + redeploy the stack from git, restore the volume, confirm nodes
& keys return with no manual step.

---

## 7. Rollback to Tailscale (kept as fallback)

Tailscale is **still installed** on the Dell; only its session was stopped. To revert the owner path:
```sh
sudo tailscale down    # leave Headscale
sudo tailscale up      # re-point the Dell to Tailscale SaaS — old path restored, no re-provision
```
To return to Headscale, re-run the §2 step-6 `tailscale up --login-server ...`.

---

## 8. Plan B — Traefik TCP/SNI passthrough (if the h1 route fails the handshake)

The primary edge integration forces **HTTP/1.1** on the `headscale` router (TLSOption
`headscale-h1@file`) so the `Upgrade: tailscale-control-protocol` survives Traefik (traefik#12609 drops
it over HTTP/2). If a **real client enroll (T017) still fails to connect** on your pinned client/server
pair, switch to raw TCP passthrough — Traefik forwards the TLS stream untouched and Headscale terminates
its own TLS:

1. In `stacks/traefik/compose.yaml`, add a **TCP router** on the `websecure` entrypoint:
   `HostSNI(\`headscale.ragnaforge.xyz\`)`, `tls.passthrough=true`, service → `headscale:443`.
   (TCP+SNI routers coexist with the HTTP routers on the same 443 entrypoint.)
2. In `stacks/headscale/compose.yaml`, **remove** the HTTP router labels + the `headscale-h1` option use,
   and give Headscale its **own** cert: set `server_url` https and enable built-in ACME
   **TLS-ALPN-01** (challenge over the passthrough :443) or mount a cert
   (`tls.cert_path`/`tls.key_path`); listen on `:443`.
3. Recreate both stacks; re-run the assert + T017 enroll.

Trade-off: passthrough bypasses the upgrade bug entirely but **can't reuse** Traefik's wildcard cert.

---

## 9. Version / change log

- Pinned: `headscale/headscale:0.26.1` (avoid 0.27.0 — #2870). Re-diff `config-example.yaml` on bump.
- See `specs/011-headscale-vpn/` for spec, plan, research (R1–R11), and the SC drills in `quickstart.md`.
- Related: [[homeserve-headscale-traefik-h2]], [[homeserve-ipv6-exposure-xfinity]],
  [[homeserve-inline-configs-need-recreate]], [[homeserve-traefik-mac-routing]].
