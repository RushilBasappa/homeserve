# Clean Rebuild

Wipe both nodes and rebuild from code. On **fresh** machines skip step 1.
Needs: SSH to each node, this repo, a filled `.mise.toml`.

1. **Wipe** (existing boxes only) — keeps SSH + Tailscale:
   `bash scripts/cleanup-all.sh --yes`

2. **Provision** (from workstation): `make provision`

3. **Update node repos** (Dell + Mac):
   `cd ~/homeserve && git fetch origin main && git reset --hard origin/main`

4. **Komodo Core** (Dell): `cp komodo/bootstrap/core.env.example komodo/bootstrap/core.env && make komodo-core`
   - http://10.0.0.70:9120 → register first user (= admin).
     If blocked: set `KOMODO_DISABLE_USER_REGISTRATION=false` in core.env, recreate, register, set back `true`, recreate.
   - Create an API key. **The Copy button doesn't work** — open DevTools (Inspect)
     and read the **key** and **secret** out of the page. Put them in `.mise.toml`
     as `KOMODO_API_KEY` / `KOMODO_API_SECRET`.

5. **Periphery** (Dell + Mac): `make komodo-periphery`

6. **Deploy** (from workstation, via Core API with the key above):
   - `make edge-network` (run on Dell — creates `traefik` network)
   - CreateResourceSync `homeserve` (repo `RushilBasappa/homeserve`, path `komodo/`)
   - `RunSync homeserve` → registers both servers + all stacks
   - `DeployStack` each: traefik, adguard, homepage, whoami, cloudflare-ddns, wg-easy

7. **Manual** (not in Git): AdGuard first-run wizard · wg-easy add peers · approve Tailscale `10.0.0.0/24` route.

**Other house:** first edit IPs/hostnames/domain in `provision/inventory.yml`,
`komodo/servers.toml`, `komodo/variables.toml`, and secrets in `.mise.toml`.
