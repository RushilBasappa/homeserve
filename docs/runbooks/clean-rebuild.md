# Clean Rebuild

Wipe both nodes and rebuild from code. On **fresh** machines skip step 1.
Needs: SSH to each node, this repo, a filled `.mise.toml`.

1. **Wipe** (existing boxes only) — keeps SSH + Tailscale:
   `bash scripts/cleanup-all.sh --yes`

2. **Provision** (from workstation): `make provision`

3. **Update node repos** (Dell + Mac):
   `cd ~/homeserve && git fetch origin main && git reset --hard origin/main`

4. **Edge network first** (Dell) — Core now attaches to it, so create it BEFORE Core:
   `make edge-network`   (creates the `traefik` network)

5. **Komodo Core** (Dell): `cp komodo/bootstrap/core.env.example komodo/bootstrap/core.env && make komodo-core`
   - http://10.0.0.70:9120 → register first user (= admin).
     If blocked: set `KOMODO_DISABLE_USER_REGISTRATION=false` in core.env, recreate, register, set back `true`, recreate.
   - Create an API key. **The Copy button doesn't work** — open DevTools (Inspect)
     and read the **key** and **secret** out of the page. Put them in `.mise.toml`
     as `KOMODO_API_KEY` / `KOMODO_API_SECRET`.

6. **Periphery** (Dell + Mac): `make komodo-periphery`

7. **Deploy** (from workstation, via Core API with the key above):
   - CreateResourceSync `homeserve` (repo `RushilBasappa/homeserve`, path `komodo/`)
   - `RunSync homeserve` → registers both servers + all stacks
   - `DeployStack` each: traefik, adguard, homepage, whoami, cloudflare-ddns, wg-easy

8. **Configure AdGuard** (scriptable — admin, `*.ragnaforge.xyz→10.0.0.70` rewrite,
   upstreams+DNSSEC, blocklist; needs `ADGUARD_ADMIN_PASSWORD` in `.mise.toml`):
   `ssh ragnaforge-dell 'cd ~/homeserve && mise exec -- ./scripts/adguard-setup.sh'`

9. **Manual** (truly not in Git): wg-easy add peers · point clients' DNS at
   `10.0.0.70` (router DHCP or per-device) · approve Tailscale `10.0.0.0/24` route.

Apps then resolve at `home` / `whoami` / `komodo` / `adguard` / `vpn` `.ragnaforge.xyz`.

**Other house:** first edit IPs/hostnames/domain in `provision/inventory.yml`,
`komodo/servers.toml`, `komodo/variables.toml`, and secrets in `.mise.toml`.
