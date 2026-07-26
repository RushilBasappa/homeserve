# Quickstart & Validation: Self-Hosted Headscale VPN

**Feature**: 011-headscale-vpn | **Date**: 2026-07-26

Runnable drills that prove the feature end-to-end. Full step-by-step (per-platform onboarding, key
rotation, backup) lives in `docs/runbooks/headscale.md`; this file is the validation checklist that maps
to the spec's Success Criteria. Commands are illustrative — pin the actual image tag and re-diff
`config-example.yaml` first (research R1).

## Prerequisites

- `stacks/headscale/` deployed via Komodo on the Dell; `headscale-data` volume present.
- Traefik file provider carries the `headscale-h1` TLSOption (`alpnProtocols: ["http/1.1"]`) and the
  `headscale.ragnaforge.xyz` router → `headscale:8080`.
- `cloudflare-ddns` publishes `headscale.ragnaforge.xyz` → home public IP.
- xFi router forwards **443/tcp** and **3478/udp** → `10.0.0.70`.
- The Dell's Tailscale client re-pointed at Headscale as the `10.0.0.0/24` subnet router.

## 0. Config validates before exposure (FR-011, INV-6)

```sh
docker exec headscale headscale configtest        # exits 0 on valid config
docker exec headscale headscale nodes list         # server responds
```
Run the Ansible assert: `ansible-playbook stacks/headscale/configure/assert.yml`.
**Expected**: configtest passes; control TLS serves a valid `*.ragnaforge.xyz` cert; STUN answers on
`10.0.0.70:3478`. Only then open the router forwards.

## 1. Owner reaches the fleet off-LAN via Headscale (SC-001, SC-004)

```sh
# Dell (subnet router):
sudo tailscale up --login-server https://headscale.ragnaforge.xyz --advertise-routes=10.0.0.0/24
docker exec headscale headscale nodes approve-routes ... # or auto-approved via policy

# Owner laptop, TETHERED to a phone (off home WiFi):
sudo tailscale up --login-server https://headscale.ragnaforge.xyz --authkey <owner-key>
tailscale status                                   # shows headscale peers, not Tailscale SaaS
curl -I https://whoami.ragnaforge.xyz              # 200, valid wildcard cert
```
**Expected**: tunnel up in seconds; `whoami.ragnaforge.xyz` resolves to `10.0.0.70` (AdGuard split DNS)
and loads over HTTPS with the padlock, **in <30 s from cold connect**; no session depends on Tailscale
SaaS.

## 2. Non-technical guest enrolls & connects on cellular (SC-002, SC-003)

```sh
# Owner mints a time-boxed single-use key (CLI or the web UI):
docker exec headscale headscale preauthkeys create --user guests --expiration 24h
```
Guest, on a **phone with WiFi off (cellular only)**: install the Tailscale app → set custom
coordination server `https://headscale.ragnaforge.xyz` → paste the key → open a shared app's
`*.ragnaforge.xyz` name.
**Expected**: joins with one paste, **<5 min**, no terminal; the shared app loads over HTTPS on
cellular (the exact case wg-easy failed). Force a relay path (block STUN/UDP on the test network) and
confirm it **still loads** via DERP (SC-003).

## 3. Guest is scoped to the edge only (FR-009, R6)

From the guest device: `curl -I https://<shared-app>.ragnaforge.xyz` → **200**; `ssh 10.0.0.70` and
`curl http://10.0.0.70:3000` (AdGuard admin) → **blocked/timeout**.
**Expected**: guests reach `:443` only; SSH/Komodo/NFS/AdGuard-admin denied by ACL. (Per-*app* scoping
is app-level auth — see R6.)

## 4. Public surface is exactly two ports; no v6 leak (SC-005, SC-009)

From an **external** host: `nmap -Pn -p 443,3478,80,51820 <home-public-ip>` and a UDP probe of 3478.
`nmap -6 -Pn <dell-public-v6>` for new services.
**Expected**: only **443/tcp** + **3478/udp** open; **51820/udp closed** (wg-easy retired, SC-006); no
new service on public IPv6.

## 5. wg-easy is gone; Tailscale rolls back (SC-006, SC-007)

```sh
# wg-easy removed:
docker ps | grep wg-easy        # empty
curl -I https://wg.ragnaforge.xyz   # no route

# Rollback drill:
sudo tailscale down             # (was already down post-cutover)
sudo tailscale up               # re-points the Dell to Tailscale SaaS — old owner path restored <10 min
```
**Expected**: wg-easy stack/UI/port gone; a single `tailscale up` restores the prior path with no
re-provision (FR-017).

## 6. Reproducibility & backup (SC-008)

Destroy + redeploy the stack from the repo (Komodo) and restore `headscale-data` from a snapshot;
confirm nodes/keys return. **Expected**: the tailnet reproduces from code + the volume snapshot, no
undocumented manual step.

---

### Success-criteria coverage

| Drill | Criteria |
|---|---|
| 0 | FR-011, INV-6 |
| 1 | SC-001, SC-004 |
| 2 | SC-002, SC-003 |
| 3 | FR-009 |
| 4 | SC-005, SC-009 |
| 5 | SC-006, SC-007 |
| 6 | SC-008 |
