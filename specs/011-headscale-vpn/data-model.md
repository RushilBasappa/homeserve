# Data Model: Self-Hosted Headscale VPN

**Feature**: 011-headscale-vpn | **Date**: 2026-07-26

This is an infrastructure feature; the "entities" are Headscale's control-plane objects and the fleet
config artifacts, not application database tables. Persistence is Headscale's SQLite DB + key files on
the Dell-local `headscale-data` volume (R9).

---

## Entities

### 1. Control server (Headscale instance)
The self-hosted coordination plane. Singleton, on the Dell.

| Attribute | Value / source |
|-----------|----------------|
| `server_url` | `https://headscale.ragnaforge.xyz` (public; Cloudflare-resolved; TLS terminated by Traefik) |
| `listen_addr` | `0.0.0.0:8080` (plain HTTP; TLS off — Traefik terminates) |
| `metrics_listen_addr` / `grpc_listen_addr` | internal only — **not** published, **not** forwarded |
| DERP embedded | `derp.server.enabled: true`, `region_id`, `stun_listen_addr: 0.0.0.0:3478` |
| State | SQLite `db.sqlite`, `noise_private_key`, DERP `private_key` → `headscale-data` volume |
| Config | `config.yaml` + `policy.hujson` (non-secret, inline `configs:` in compose) |

**Validation**: `headscale configtest` passes; TLS serves a valid `*.ragnaforge.xyz` cert; STUN answers
on `10.0.0.70:3478`. Fail closed before the router forward is opened.

### 2. User (namespace)
The identity a node belongs to; the unit ACLs are written against.

| User | Purpose | ACL scope |
|------|---------|-----------|
| `owner` | The homelab owner's devices | full (`*:*`) |
| `guests` | Family/friends | `10.0.0.0/24:443` + DNS `10.0.0.70:53` only (R6) |

### 3. Tailnet node
An enrolled device.

| Attribute | Notes |
|-----------|-------|
| identity | node key; belongs to exactly one user |
| tailnet IP | from `prefixes.v4` (`100.64.0.0/10`) |
| tags | e.g. `tag:subnet-router` (the Dell), used by `autoApprovers` |
| routes | the Dell advertises `10.0.0.0/24` (auto-approved); others advertise none |
| key expiry | node keys expire → re-auth; guest keys time-boxed |

**Special node — the Dell (subnet router)**: runs the Tailscale client pointed at Headscale with
`--advertise-routes=10.0.0.0/24`, tagged `tag:subnet-router`; its route is auto-approved so every node
reaches `10.0.0.70` (AdGuard + Traefik + apps).

### 4. Pre-authorized key
The credential the owner hands a guest to enroll.

| Attribute | Value |
|-----------|-------|
| user | `guests` (or `owner`) |
| expiration | time-boxed (e.g. 24h) |
| reusable | single-use default; `--reusable` for a shared device |
| state | revocable/expirable by the owner (FR-010) |

### 5. Access policy (ACL)
HuJSON policy file, `policy.mode: file`. Defines `groups`/`users` → `acls` (owner full; guests →
edge:443 only) and `autoApprovers.routes` (`10.0.0.0/24` from `tag:subnet-router`). See R6 for the
vhost-scoping limitation.

### 6. Relay (DERP)
The embedded relay carrying traffic when direct P2P fails. `region_id` local; reachable via the same
:443 (HTTPS) + STUN :3478/udp. Fallback path, always available (FR-008).

---

## Relationships

```
Control server ──has many──▶ Users ──has many──▶ Nodes
      │                         │
      │ enforces                │ enrolled via
      ▼                         ▼
   Access policy          Pre-authorized keys
      │ approves
      ▼
  Routes (10.0.0.0/24 from the Dell subnet-router node)
      │ makes reachable
      ▼
  LAN edge 10.0.0.70 (AdGuard DNS + Traefik + apps)
```

## State & lifecycle

- **Node key expiry** → node must re-authenticate; guest keys are additionally time-boxed.
- **Config/policy edit** → inline `configs:` change requires a container **recreate**
  (DestroyStack + DeployStack), not just redeploy ([[homeserve-inline-configs-need-recreate]]).
- **Backup/restore** → snapshot the `headscale-data` volume (DB + keys); restore reproduces the tailnet.
- **Rollback** → `tailscale up` on the Dell re-points to Tailscale SaaS (FR-017), no re-provision.
