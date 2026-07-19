# Phase 0 Research: Foundation & Repo Scaffolding

No `NEEDS CLARIFICATION` markers remained in the spec; the master plan (`PLAN.md`)
fixes the design decisions. This document records the rationale for the choices
that shape the scaffolding, so later phases inherit settled conventions.

## R1 — Repository layout

- **Decision**: Top-level `stacks/`, `provision/`, `komodo/`, `docs/`, plus root
  `PLAN.md` and `README.md`. One directory per Compose stack under `stacks/`.
- **Rationale**: Matches the master plan §Phase 0 verbatim; a directory-per-stack
  layout maps cleanly onto Komodo Resource Sync (Phase 2) and Docker Compose, and
  keeps each app self-contained and independently deployable.
- **Alternatives considered**: A flat `docker-compose.yml` with all services
  (rejected — no per-stack isolation, hard for Komodo to manage individually); a
  Kustomize/Helm-style tree (rejected — the plan explicitly retires k3s in favor
  of plain Compose).

## R2 — Secret handling pattern

- **Decision**: Track a placeholder-only `.mise.toml.example`; keep the real
  `.mise.toml` gitignored. `mise` renders the real values into env for Komodo.
- **Rationale**: The plan's north star requires "secrets never leak into the
  shareable report." An example file gives contributors a complete, self-documenting
  list of required secrets while guaranteeing no real value is ever committed. The
  repo stays safe to share publicly.
- **Alternatives considered**: Committed-but-encrypted secrets (SOPS/age) —
  heavier tooling, not needed at Phase 0 and not chosen by the plan; a plain
  `.env.example` — `mise` is the plan's chosen secret manager, so mirror its
  file format.

## R3 — Preventing accidental secret commits

- **Decision**: `.gitignore` excludes `.mise.toml`, `.env` / `*.env`, and a
  generated-artifacts location. Verified via `git check-ignore` and a `grep`
  sweep proving no real secret values are tracked.
- **Rationale**: Belt-and-suspenders — the ignore rules stop the common leak, and
  the placeholder-only example plus a grep check catch the rest. Cheap to verify
  in `quickstart.md`.
- **Alternatives considered**: A pre-commit secret scanner (e.g. gitleaks) —
  valuable later, but adds a dependency and hook setup out of scope for a
  no-runtime Phase 0; can be added in Phase 10 (maintenance).

## R4 — Documenting empty directories

- **Decision**: Each initially-empty directory (`stacks/`, `provision/`,
  `komodo/`) carries a one-paragraph `README.md` describing what belongs there.
- **Rationale**: Git does not track empty directories, and the README doubles as
  in-place documentation supporting SC-001 (newcomer understands each dir fast).
- **Alternatives considered**: `.gitkeep` placeholder files (rejected — keeps the
  dir but documents nothing).

## R5 — README as the growing shareable report

- **Decision**: README is a phase-aligned outline with placeholder sections for
  Phases 1–12; it summarizes purpose + current phase status and links to `PLAN.md`
  and `docs/CONVENTIONS.md` rather than duplicating them.
- **Rationale**: Gives every later phase a home for its documentation, avoiding a
  large Phase 11 documentation-debt cleanup. Linking (not duplicating) keeps a
  single source of truth.
- **Alternatives considered**: Deferring all README content to Phase 11 (rejected
  — later phases would have nowhere to append, causing rework).

## R6 — Conventions document scope

- **Decision**: `docs/CONVENTIONS.md` covers stack naming, port allocation,
  Traefik routing labels, the "stateful data → Dell" rule (config vs. shared
  media placement), and a step-by-step new-app checklist.
- **Rationale**: A single conventions source prevents drift across 12 phases and
  encodes the load-bearing architectural rule (stateful state centralized on the
  Dell → one backup source) before any stack exists to violate it.
- **Alternatives considered**: Per-directory convention notes (rejected —
  fragments the source of truth); leaving conventions implicit (rejected — causes
  inconsistent stacks and rework).
