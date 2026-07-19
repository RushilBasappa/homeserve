# adguard — first-run configuration

AdGuard Home manages its own `AdGuardHome.yaml` (schema-versioned, contains the
admin bcrypt hash), so this repo does **not** commit that file — it would leak a
credential hash and drift across versions. Instead, apply the settings below once
via the first-run wizard; they then persist on the `adguard-conf` volume on the
Dell. This is the "document first-run steps" path from tasks.md T019.

Reference: research **R3**, contract
[`dns-resolution-contract.md`](../../specs/004-edge-dns-tls/contracts/dns-resolution-contract.md),
validated by quickstart **Scenario 2** (SC-005).

## 0. Prerequisite — `:53` must be free on the Dell

AdGuard needs to bind host `:53`. On **this** fleet `:53` is already free (the Dell
runs no `systemd-resolved`, and Tailscale's resolver lives at `100.100.100.100`,
not a host `:53` bind), so no prep is needed — `provision/tasks/edge-dns.yml` just
asserts it. Confirm before deploying:

```sh
sudo ss -lunp | grep ':53' || echo ":53 free"
```

> ⚠️ Do **not** repoint `/etc/resolv.conf` on the Dell — Tailscale owns it
> (MagicDNS). Creating a `/run/systemd/resolve/...` symlink on a host without
> `systemd-resolved` breaks all name resolution. If a future host *does* run
> `systemd-resolved`, `edge-dns.yml` disables only its stub listener.

## 1. Setup — automated (recommended)

After deploying the `adguard` stack, run the setup script on the Dell. It drives
AdGuard's HTTP API to complete first-run config (admin user, DNS `:53`/web `:3000`,
the wildcard rewrite, upstreams+DNSSEC, and the ad blocklist) — reproducible and
secret-free (the admin password comes from `${ADGUARD_ADMIN_PASSWORD}` in the
gitignored `.mise.toml`):

```sh
cd ~/homeserve && mise exec -- ./scripts/adguard-setup.sh
```

That covers sections 2–4 below. The manual wizard steps are kept as reference /
for tweaking in the UI at `http://10.0.0.70:3000` (LAN/Tailscale only).

### Manual wizard (alternative / reference)

1. Browse to `http://10.0.0.70:3000` (LAN or Tailscale — never router-forwarded).
2. **Admin Web Interface**: keep port `3000`. **DNS server**: `53`.
3. Create the admin user; set the password to the value of
   `ADGUARD_ADMIN_PASSWORD` from your gitignored `.mise.toml` (AdGuard stores it
   as a bcrypt hash in `AdGuardHome.yaml` on the volume — never in git).

## 2. Wildcard DNS rewrite (the single-address answer — FR-008)

**Filters → DNS rewrites → Add**:

| Domain | Answer |
|---|---|
| `*.ragnaforge.xyz` | `10.0.0.70` |

Every `<name>.ragnaforge.xyz` now resolves to the Dell for **all** clients (no
split-horizon). Reachability off-LAN is solved by subnet routing (Tailscale
`--advertise-routes`, wg-easy `AllowedIPs`), not DNS — research R9.

> If a client's DNS-rebind protection blocks a private-IP answer for our own
> domain, that is expected/allowed here (FR-009) — whitelist `ragnaforge.xyz`.

## 3. Upstream resolvers + DNSSEC (FR-008)

**Settings → DNS settings → Upstream DNS servers** (parallel or load-balance):

```
https://dns.quad9.net/dns-query
https://cloudflare-dns.com/dns-query
```

- **Bootstrap DNS**: `9.9.9.9`, `1.1.1.1`.
- Enable **Use DNSSEC**.
- Public domains keep resolving normally (SC-005) — this is not a walled garden.

## 4. Blocklists (FR-010)

**Filters → DNS blocklists**: keep the default **AdGuard DNS filter**, and add a
couple of well-known lists (e.g. AdAway, and OISD if desired). Ad/tracker domains
are then blocked network-wide without breaking legitimate domains.

## 5. Point clients at the resolver

- **LAN**: set the Xfinity gateway's DHCP DNS to `10.0.0.70` (or set it per
  device for testing).
- **wg-easy** clients: pushed automatically via `WG_DEFAULT_DNS=10.0.0.70`.
- **Tailscale**: optional split-DNS for `ragnaforge.xyz → 10.0.0.70` in the admin
  console.

## Verify (quickstart Scenario 2)

```sh
nslookup home.ragnaforge.xyz 10.0.0.70     # → 10.0.0.70
nslookup example.com          10.0.0.70     # → resolves normally
nslookup doubleclick.net      10.0.0.70     # → blocked (0.0.0.0 / NXDOMAIN)
```
