# Phase 0 Data Model: Foundation & Repo Scaffolding

This phase has no runtime data store. The "entities" are the repository artifacts
and their required content. Each maps to functional requirements in `spec.md`.

## Entity: Repository Skeleton

The set of directories and root files defining where every future artifact lives.

| Field | Required content | Source FR |
|---|---|---|
| `stacks/` | Directory + `README.md` ("one dir per Compose stack") | FR-001 |
| `provision/` | Directory + `README.md` (lean provisioning) | FR-002 |
| `komodo/` | Directory + `README.md` (resource-sync definitions) | FR-003 |
| `docs/` | Directory holding `CONVENTIONS.md` | FR-004 |
| `PLAN.md` | Master plan (already present), linked from README | FR-005 |
| `README.md` | Purpose, current phase status, links, phase-aligned outline | FR-012 |

**Validation rules**:
- Every listed directory MUST exist and MUST document its purpose (own README or
  the conventions doc). (FR-001..FR-004)
- The repo MUST be understandable with nothing running/built. (FR-014)

## Entity: Example Secrets File (`.mise.toml.example`)

Tracked, placeholder-only template a contributor copies to create the real
`.mise.toml`.

| Field | Required content | Source FR |
|---|---|---|
| Cloudflare API token | Labeled placeholder, no real value | FR-006, FR-007 |
| Commercial-VPN WireGuard egress credentials | Labeled placeholder | FR-006, FR-007 |
| Tailscale auth key | Labeled placeholder | FR-006, FR-007 |
| Any other secret referenced by `PLAN.md` | Labeled placeholder | FR-007 |

**Validation rules**:
- MUST contain zero real secret values. (FR-013)
- MUST enumerate every secret the master plan references. (FR-007 / SC-002 = 100%)
- Each entry MUST be an obvious placeholder so a missing fill-in is visible on
  inspection. (edge case)

## Entity: Ignore Rules (`.gitignore`)

Declares paths that must never enter version control.

| Field | Required content | Source FR |
|---|---|---|
| Real secrets file | `.mise.toml` ignored | FR-008 |
| Environment files | `.env`, `*.env` ignored | FR-008 |
| Generated artifacts | Generated/rendered output path ignored | FR-008 |

**Validation rules**:
- After copying the example to the real `.mise.toml`, `git check-ignore` MUST
  report it ignored (0 accidental staging). (SC-004)

## Entity: Conventions Document (`docs/CONVENTIONS.md`)

Single source of truth for how stacks are built.

| Field | Required content | Source FR |
|---|---|---|
| Naming conventions | Stack/container/host naming rules | FR-009 |
| Port conventions | Port allocation approach | FR-009 |
| Routing labels | Traefik label conventions | FR-009 |
| Data placement rule | "Stateful → Dell"; config vs. shared media | FR-010 |
| New-app checklist | Step-by-step add-an-app procedure | FR-011 |

**Validation rules**:
- A contributor MUST be able to place a hypothetical app using only this document.
  (SC-005)

## Entity: README (Shareable Report)

The self-documenting entry point and phase-aligned skeleton.

| Field | Required content | Source FR |
|---|---|---|
| Purpose | Project summary | FR-012 |
| Current phase status | States what is / isn't built | FR-012, edge case |
| Links | To `PLAN.md` and `docs/CONVENTIONS.md` | FR-012 |
| Phase-aligned outline | Placeholder sections for later phases | FR-012 |

**Validation rules**:
- MUST contain no real secret values — only references to the placeholder pattern.
  (FR-013)
