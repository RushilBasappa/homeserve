# Contract — Edge Routing (Traefik labels)

The interface every HTTP app uses to become reachable at
`https://<app>.ragnaforge.xyz`. This is the stable contract later phases depend on;
it mirrors `docs/CONVENTIONS.md` → "Traefik routing labels" and is verified by
`quickstart.md` (US1/US2). Research: R1, R2, R10.

## Provider obligations (the edge — `traefik`)

- **MUST** discover routes from Docker **labels** on services attached to the external
  `traefik` network — with **no edit to Traefik's own config** to add/change/remove a
  route. (FR-002)
- **MUST** route by request Host: `<app>.ragnaforge.xyz` → the container/port named in
  that app's labels. (FR-001)
- **MUST** serve every matched route over HTTPS using the shared wildcard
  `*.ragnaforge.xyz` cert (see `tls-certificate-contract.md`); apps never request
  their own cert. (FR-003, SC-003)
- **MUST** redirect `http://` → `https://` globally (entryPoint redirection), not
  per-app. (FR-004, SC-006)
- **MUST** return a clear not-found for a Host no running stack claims (no routing to
  an unrelated app). (SC-006)
- **MUST** drop a route within seconds when its stack stops (no stale route). (FR-002)

## Consumer obligations (each app stack)

- **MUST** attach to the external `traefik` network and carry the canonical label set,
  with router/service name == **stack name** and `server.port` == the app's
  **internal** listen port:
  ```yaml
  networks: [traefik]
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.<app>.rule=Host(`<app>.ragnaforge.xyz`)"
    - "traefik.http.routers.<app>.entrypoints=websecure"
    - "traefik.http.routers.<app>.tls=true"
    - "traefik.http.services.<app>.loadbalancer.server.port=<container-port>"
  ```
- **MUST NOT** publish host `ports:` for an HTTP service (reached only via Traefik).
- **MUST NOT** declare its own `certresolver`/domains — it reuses the wildcard.
- A **non-HTTP** service (e.g. a worker) carries **no** labels and is simply not
  routed (the edge ignores it, no error). (Edge case)

## Postconditions (observable)

1. Deploying a labelled stack via the Phase-2 Komodo workflow makes
   `https://<app>.ragnaforge.xyz` load within **30 s**, with a trusted cert, no
   Traefik config edit. (SC-002)
2. A brand-new subdomain is served under the **existing** wildcard — no new issuance.
   (SC-003)
3. `http://<app>.ragnaforge.xyz` 301/308-redirects to `https://`. (SC-006)
4. An unclaimed Host returns 404, not a wrong app. (SC-006)

## Invariants

- One name everywhere: directory = stack = router/service = subdomain = Homepage entry.
- No per-app TLS state; the only cert store is Traefik's `acme.json`.
