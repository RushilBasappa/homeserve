# Contract — Wildcard TLS Certificate

How the one `*.ragnaforge.xyz` certificate is obtained, renewed, and reused. Research:
R2, R12. Verified by `quickstart.md` (US3).

## Obligations

- The edge **MUST** obtain a **wildcard** cert (`main: ragnaforge.xyz`, `sans:
  *.ragnaforge.xyz`) from **Let's Encrypt** via ACME **DNS-01** against the
  **Cloudflare** zone — **no inbound port** required for issuance. (FR-005)
- It **MUST** authenticate to Cloudflare with `CF_DNS_API_TOKEN=${CLOUDFLARE_API_TOKEN}`
  (DNS-edit scope on `ragnaforge.xyz`); the token value **MUST NOT** appear in any
  tracked file. (FR-014, SC-009)
- It **MUST** persist `acme.json` (perms `0600`) on the Dell volume `traefik-acme` and
  **reuse** it across restarts rather than re-requesting. (FR-007, SC-007)
- It **MUST** renew automatically **before expiry**, with no operator action and no
  user-visible interruption, using a **lifetime-agnostic** policy — no hardcoded
  lifetime/profile, so LE's 45-day (2026-05-13) / 64-day (2027) shifts need no change.
  (FR-006, SC-004)
- On **missing/invalid** credentials it **MUST** fail with a clear, logged error and
  **MUST NOT** silently serve an untrusted/self-signed cert. (US3 acceptance #3)

## Postconditions (observable)

1. From a fresh volume the edge obtains a valid `*.ragnaforge.xyz` cert unattended;
   the served cert is **LE-issued** and browser-trusted. (SC-001, SC-004)
2. Restarting the edge does **not** trigger a new issuance (persisted cert reused).
   (SC-007)
3. A new subdomain is covered by the existing wildcard with **zero** issuance steps.
   (SC-003)

## Notes / non-goals

- ARI (ACME Renewal Info) is a welcome enhancement where the client supports it, but
  Traefik's default renewal window already covers every profile in use; **not**
  opting into the 6-day short-lived profile.
- CA is swappable in principle (`caServer` → ZeroSSL / Google Trust Services, both
  DNS-01 peers) with no other change; not exercised this phase.
