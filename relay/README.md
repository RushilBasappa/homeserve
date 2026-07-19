# Cloud relay — conditional CGNAT fallback (research R8; contract remote-access)

**Build this ONLY on a preflight NO-GO** (`make preflight`). If preflight returns
GO, skip this entirely and use the direct xFi port-forward path.

When the home has no usable public inbound (CGNAT, or the xFi gateway won't
forward UDP reliably), a small always-on VPS with a **static public IP** relays
the one WireGuard port to the Dell over the existing Tailscale tailnet — so remote
family/friends reach wg-easy with **no home inbound port at all** (FR-022, SC-014).
The client `.conf` and the end-user experience are identical to the direct path.

```
family device ──UDP 51820──▶ VPS (public static IP, on tailnet)
                                 │  DNAT 51820/udp
                                 ▼
                            Dell Tailscale IP :51820  ──▶ wg-easy ──▶ edge
```

`vpn.ragnaforge.xyz` points at the **VPS static IP** on this path, so Cloudflare
DDNS is **not needed** (the `cloudflare-ddns` stack can stay stopped).

The VM itself is **out of this repo** (a few $/mo on any provider — Hetzner, Fly,
a small DO/Vultr instance). This is the recipe to reproduce it.

## Prerequisites

- A VPS with a **static public IPv4** and root.
- The **same Tailscale tailnet** as the Dell (a Tailscale auth key).
- The Dell's Tailscale IP — find it with `tailscale ip -4` on the Dell (a
  `100.x.y.z` address). Referenced below as `DELL_TS_IP`.

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

## 3. DNAT inbound UDP 51820 → the Dell over Tailscale (nftables)

Replace `DELL_TS_IP` with the Dell's Tailscale IPv4. `eth0` = the VPS public NIC;
`tailscale0` = the tailnet interface.

```sh
sudo tee /etc/nftables.conf >/dev/null <<'EOF'
table inet relay {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    # Public UDP 51820 → the Dell's Tailscale IP.
    iifname "eth0" udp dport 51820 dnat ip to DELL_TS_IP:51820
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

> `socat` alternative (simpler, no persistence): `socat -T15
> UDP4-RECVFROM:51820,fork UDP4-SENDTO:DELL_TS_IP:51820` under a systemd unit.
> nftables DNAT is preferred — kernel-level, survives reboot, lower overhead.

## 4. Open UDP 51820 on the VPS firewall

Allow inbound `udp/51820` in the provider's security group / `ufw allow 51820/udp`.
**Only** this port — nothing else public on the relay.

## 5. Point the endpoint name at the VPS

Set the `vpn.ragnaforge.xyz` A record (Cloudflare) to the VPS **static** IP. Stop
the `cloudflare-ddns` stack — it is unnecessary on this path.

## 6. Deploy wg-easy as usual

`WG_HOST=vpn.ragnaforge.xyz` already resolves to the VPS; wg-easy is unchanged.
Client `.conf`s use `Endpoint = vpn.ragnaforge.xyz:51820` exactly as on the direct
path — the relay is invisible to end users.

## Verify

- From an off-LAN/off-Tailscale device, import a `.conf` and connect via
  `vpn.ragnaforge.xyz` → `https://whoami.ragnaforge.xyz` loads over trusted HTTPS.
- A port scan of the **home** public IP shows **nothing** (no home inbound); the
  only public port anywhere is UDP 51820 on the **VPS** (SC-010/014).
