# Cloud relay — conditional CGNAT fallback (headscale; contract remote-access, FR-016)

**Build this ONLY on a preflight NO-GO** (`make preflight`). If preflight returns
GO, skip this entirely and use the direct xFi port-forward path (443/tcp + 3478/udp
→ the Dell, per `docs/runbooks/headscale.md`).

When the home has no usable public inbound (CGNAT, or the xFi gateway won't forward
reliably), a small always-on VPS with a **static public IP** relays Headscale's public
ports to the Dell — so remote family/friends reach the **Headscale** control plane with
**no home inbound port at all**. The client experience is identical to the direct path.

> **Why this still works while we're migrating off Tailscale's cloud:** the fleet's
> *remote access* is now Headscale, but the VPS↔Dell hop rides the **preserved
> Tailscale tailnet** (we keep the Tailscale client installed — [[homeserve-portability-goal]]).
> That gives the relay a ready-made private path to the Dell without exposing any home
> port — the one job Tailscale still does here.

```
client device ──TCP 443 / UDP 3478──▶ VPS (public static IP, on the Tailscale tailnet)
                                          │  DNAT 443/tcp + 3478/udp
                                          ▼
                                     Dell Tailscale IP  ──▶ Traefik:443 → headscale
                                                        └─▶ headscale STUN :3478 ──▶ edge
```

`headscale.ragnaforge.xyz` points at the **VPS static IP** on this path, so Cloudflare
DDNS is **not needed** (the `cloudflare-ddns` stack can stay stopped).

The VM itself is **out of this repo** (a few $/mo on any provider — Hetzner, Fly, a
small DO/Vultr instance). This is the recipe to reproduce it.

## Prerequisites

- A VPS with a **static public IPv4** and root.
- The **same Tailscale tailnet** as the Dell (a `TAILSCALE_AUTHKEY`).
- The Dell's Tailscale IP — `tailscale ip -4` on the Dell (a `100.x.y.z`). Below: `DELL_TS_IP`.
- **On the Dell (relay-path only):** Headscale's STUN must be reachable on the Dell's
  Tailscale interface, not just `10.0.0.70`. On this path set the STUN publish in
  `stacks/headscale/compose.yaml` to `"0.0.0.0:3478:3478/udp"` (still no *public* home
  exposure — the home has no inbound at all here), or bind it to `DELL_TS_IP`.

## 1. Join the VPS to the tailnet

```sh
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey "$TAILSCALE_AUTHKEY" --hostname ragnaforge-relay
tailscale status        # confirm the Dell is visible on the tailnet
```

## 2. Enable IPv4 forwarding on the VPS

```sh
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-relay.conf
sudo sysctl --system
```

## 3. DNAT inbound 443/tcp + 3478/udp → the Dell over Tailscale (nftables)

Replace `DELL_TS_IP` with the Dell's Tailscale IPv4. `eth0` = the VPS public NIC;
`tailscale0` = the tailnet interface.

```sh
sudo tee /etc/nftables.conf >/dev/null <<'EOF'
table inet relay {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    # Public 443/tcp (Headscale control + DERP relay) → the Dell's Traefik.
    iifname "eth0" tcp dport 443  dnat ip to DELL_TS_IP:443
    # Public 3478/udp (STUN) → the Dell's Headscale.
    iifname "eth0" udp dport 3478 dnat ip to DELL_TS_IP:3478
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    # Masquerade so return traffic comes back through the VPS.
    oifname "tailscale0" masquerade
  }
}
EOF
# substitute the real Dell Tailscale IP, then load:
sudo sed -i "s/DELL_TS_IP/<paste 100.x.y.z here>/" /etc/nftables.conf
sudo systemctl enable --now nftables
sudo nft -f /etc/nftables.conf
```

> **443 is TLS-passthrough here** — the VPS does NOT terminate TLS; it forwards the
> raw TCP stream to the Dell's Traefik, which still serves the `*.ragnaforge.xyz`
> wildcard cert. The client validates the cert exactly as on the direct path.

## 4. Open 443/tcp + 3478/udp on the VPS firewall

Allow inbound `tcp/443` and `udp/3478` in the provider's security group /
`ufw allow 443/tcp && ufw allow 3478/udp`. **Only** these — nothing else public.

## 5. Point the endpoint name at the VPS

Set the `headscale.ragnaforge.xyz` A record (Cloudflare) to the VPS **static** IP.
Stop the `cloudflare-ddns` stack — it is unnecessary on this path.

## 6. Deploy headscale as usual

`server_url: https://headscale.ragnaforge.xyz` already resolves to the VPS; the stack
is unchanged apart from the STUN bind note (Prerequisites). Clients enroll with
`--login-server https://headscale.ragnaforge.xyz` exactly as on the direct path — the
relay is invisible to end users.

## Verify

- From an off-LAN/off-Tailscale device, enroll via `headscale.ragnaforge.xyz` →
  `https://whoami.ragnaforge.xyz` loads over trusted HTTPS.
- A port scan of the **home** public IP shows **nothing** (no home inbound); the only
  public ports anywhere are **443/tcp + 3478/udp** on the **VPS**.
