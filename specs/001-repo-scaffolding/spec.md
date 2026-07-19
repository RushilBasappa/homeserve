# Feature Specification: Phase 0 — Foundation & Repo Scaffolding

**Feature Branch**: `001-repo-scaffolding`

**Created**: 2026-07-18

**Status**: Draft

**Input**: User description: "read PLan and plan for phase 0"

## Overview

Phase 0 of the Ragnaforge home server plan establishes the repository skeleton,
conventions, and secret-handling practices that every later phase drops into.
The deliverable is a **clonable repository that documents itself**: a competent
friend can clone it and understand how the server is organized, how to add an
app, and how secrets are handled — without any infrastructure yet being running.

There is no application to run and no host to provision in this phase. The
"product" is the repository structure and its documentation. Success is measured
by whether a newcomer can navigate and reproduce the intended conventions purely
from the checked-in files.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Clone a self-documenting repo (Priority: P1)

As the server operator (or a competent friend reproducing the build), I clone the
repository and immediately understand its layout, the design intent, and where
each kind of artifact belongs — from the checked-in files alone, with nothing
running.

**Why this priority**: This is the core deliverable of Phase 0. Without a clear,
self-explaining skeleton, every later phase has no agreed place to put its
Compose stacks, provisioning, or docs. It is the foundation all other phases
depend on.

**Independent Test**: Clone the repo into a fresh directory and, using only the
README and directory structure, correctly state what goes in `stacks/`,
`provision/`, `komodo/`, and `docs/`, and locate the master plan and conventions.

**Acceptance Scenarios**:

1. **Given** a fresh clone, **When** the operator opens the README, **Then** it
   explains the project's purpose, the current phase status, and links to the
   master plan and conventions.
2. **Given** a fresh clone, **When** the operator lists the top-level directories,
   **Then** each of `stacks/`, `provision/`, `komodo/`, and `docs/` exists and its
   purpose is documented (via a README or the conventions doc).
3. **Given** a fresh clone, **When** the operator looks for the design rationale,
   **Then** the master plan (`PLAN.md`) is present and reachable from the README.

---

### User Story 2 - Handle secrets safely from day one (Priority: P1)

As the operator, I can see exactly which configuration values are secret and how
to supply them, while being confident that no real secret can be accidentally
committed to the repository.

**Why this priority**: The plan's north star includes "secrets never leak into
the shareable report." Establishing the placeholder-example pattern and ignore
rules before any real stack exists prevents an entire class of accidental leaks
and makes the repo safe to share publicly.

**Independent Test**: Inspect the example secrets file and the ignore rules; copy
the example to the real filename and confirm the real file is ignored by version
control while the example remains tracked.

**Acceptance Scenarios**:

1. **Given** the repo, **When** the operator opens the example secrets file,
   **Then** it lists every required secret as a clearly-labeled placeholder with
   no real value.
2. **Given** the repo, **When** the operator creates the real secrets file from
   the example, **Then** version control reports the real file as ignored and
   never stages it.
3. **Given** the ignore rules, **When** the operator inspects them, **Then** the
   real secrets file, environment files, and generated artifacts are all excluded
   from version control.
4. **Given** the example file and the master plan, **When** compared, **Then**
   every secret the plan references (e.g. Cloudflare API token, VPN egress
   credentials, Tailscale auth key) has a corresponding placeholder entry.

---

### User Story 3 - Follow one set of conventions when adding anything (Priority: P2)

As a contributor adding a new app or stack in a later phase, I follow a single
documented convention for naming, ports, routing labels, data placement, and a
new-app checklist — so every stack looks consistent and the "stateful data lives
on the Dell" rule is never accidentally violated.

**Why this priority**: Conventions prevent drift and rework across the 12 phases.
They are essential for a reproducible, low-maintenance result, but they only
deliver value once stacks start being added — so they rank just below the
skeleton and secret handling.

**Independent Test**: Open the conventions document and, using only it, describe
how a hypothetical new app would be named, where its config and media data would
live, and what steps the new-app checklist requires.

**Acceptance Scenarios**:

1. **Given** the conventions document, **When** a contributor reads it, **Then**
   it defines naming, port, and routing-label conventions for stacks.
2. **Given** the conventions document, **When** a contributor reads the data-
   placement rule, **Then** it states the "stateful → Dell" rule and where config
   versus shared media data belongs.
3. **Given** the conventions document, **When** a contributor plans a new app,
   **Then** a step-by-step new-app checklist is available to follow.

---

### User Story 4 - README grows into the shareable report (Priority: P3)

As the operator, the README is structured from the start so that each later phase
appends its section, and by the end it reads as the complete "stand it up from
zero" report that can be shared safely.

**Why this priority**: This shapes the README skeleton now so later phases have a
home for their documentation, avoiding a large documentation-debt cleanup in
Phase 11. It is valuable but not blocking for the skeleton itself.

**Independent Test**: Review the README outline and confirm it contains labeled,
initially-empty sections aligned to the plan's phases, ready to be filled in.

**Acceptance Scenarios**:

1. **Given** the README, **When** the operator reviews its structure, **Then** it
   contains a phase-aligned outline with placeholders for later phases.
2. **Given** the README, **When** the operator scans for secrets, **Then** it
   contains no real secret values, only references to the example/placeholder
   pattern.

---

### Edge Cases

- What happens when a contributor copies the example secrets file but forgets to
  fill in a placeholder? The placeholder is clearly marked as such so the missing
  value is obvious on inspection.
- How does the repo prevent a real secrets file from being committed if a
  contributor renames or relocates it? The ignore rules cover the canonical
  secret and environment filenames and a generated-artifacts location; deviations
  outside those are documented as unsupported.
- What happens when the plan later introduces a new required secret? The example
  file and conventions are the single place to add its placeholder, keeping the
  "no real secrets committed" guarantee intact.
- How does a newcomer know which phase the repo is currently at? The README
  states the current phase status so the reader knows what is and isn't built yet.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The repository MUST provide a top-level directory for Compose
  stacks (one directory per stack), with its purpose documented.
- **FR-002**: The repository MUST provide a top-level directory for provisioning
  (lean automation), with its purpose documented.
- **FR-003**: The repository MUST provide a top-level directory for orchestration
  / resource-sync definitions (Komodo), with its purpose documented.
- **FR-004**: The repository MUST provide a top-level directory for documentation.
- **FR-005**: The repository MUST include the master plan document, reachable from
  the README.
- **FR-006**: The repository MUST include an example secrets file that enumerates
  every required secret as a labeled placeholder, containing no real values.
- **FR-007**: The example secrets file MUST cover every secret referenced by the
  master plan (at minimum: Cloudflare API token, commercial-VPN WireGuard egress
  credentials, and Tailscale auth key).
- **FR-008**: The repository MUST include ignore rules that exclude the real
  secrets file, environment files, and generated artifacts from version control.
- **FR-009**: The repository MUST include a conventions document that defines
  naming, ports, and routing-label conventions for stacks.
- **FR-010**: The conventions document MUST state the "stateful data lives on the
  Dell" rule and where config versus shared media data belongs.
- **FR-011**: The conventions document MUST include a step-by-step new-app
  checklist.
- **FR-012**: The repository MUST include a README that describes the project
  purpose, states the current phase status, links to the master plan and
  conventions, and is structured as a phase-aligned outline that later phases
  extend.
- **FR-013**: No file tracked by version control MAY contain a real secret value.
- **FR-014**: The repository MUST be usable immediately after cloning with no
  build, install, or running services required to understand its structure.

### Key Entities *(include if feature involves data)*

- **Repository skeleton**: The set of top-level directories (`stacks/`,
  `provision/`, `komodo/`, `docs/`) and root files (`PLAN.md`, `README.md`) that
  define where every future artifact belongs.
- **Example secrets file**: A tracked, placeholder-only listing of every required
  secret; the template a contributor copies to create their real, ignored secrets
  file.
- **Ignore rules**: The declaration of which paths (real secrets file, env files,
  generated artifacts) must never enter version control.
- **Conventions document**: The single source of truth for naming, ports, routing
  labels, data placement, and the new-app checklist.
- **README (shareable report)**: The self-documenting entry point and the
  phase-aligned skeleton that grows into the reproduce-from-zero report.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A newcomer, given only a fresh clone, can correctly identify the
  purpose of each top-level directory in under 5 minutes using the README and
  conventions document alone.
- **SC-002**: 100% of secrets referenced in the master plan have a corresponding
  placeholder entry in the example secrets file.
- **SC-003**: Zero real secret values are present in any version-controlled file.
- **SC-004**: After copying the example secrets file to its real filename, the
  real file is reported as ignored by version control on the first check (0
  accidental staging).
- **SC-005**: A contributor can follow the new-app checklist end-to-end to
  describe placing a hypothetical app without needing to ask a clarifying
  question outside the conventions document.
- **SC-006**: The repository requires no build or running service to be
  understood — a reader reaches full comprehension from static files only.

## Assumptions

- The audience is the operator plus a "competent friend": technically capable but
  without prior knowledge of this specific setup.
- Secret management uses the plan's `mise` + `.mise.toml` / `.mise.toml.example`
  pattern; the example file is the canonical placeholder source.
- This phase produces documentation and repository structure only — no host
  provisioning, no orchestration, and no running services (those are Phases 1+).
- The master plan (`PLAN.md`) is the authoritative source of design intent; the
  README summarizes and links to it rather than duplicating it.
- "Stateful data lives on the Dell" is a fixed architectural rule for all later
  phases and is documented as such now.
- Version control is Git (implied by the plan's git-synced Komodo workflow),
  though the phase's deliverables are described in tool-agnostic terms.
- The repository is intended to be safe to share publicly, so the "no real
  secrets committed" guarantee is a hard requirement, not a preference.
