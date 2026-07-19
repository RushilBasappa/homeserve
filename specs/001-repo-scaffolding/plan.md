# Implementation Plan: Phase 0 — Foundation & Repo Scaffolding

**Branch**: `001-repo-scaffolding` | **Date**: 2026-07-18 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-repo-scaffolding/spec.md`

## Summary

Establish the Ragnaforge home-server repository skeleton: the top-level directory
layout (`stacks/`, `provision/`, `komodo/`, `docs/`), root documents (`PLAN.md`,
`README.md`), the placeholder-only secret-handling pattern (`.mise.toml.example`
+ `.gitignore`), and the conventions document that every later phase drops into.
The deliverable is a **clonable, self-documenting repository** with no running
services. Technical approach: plain files and directories in a Git repo — no
build system, no runtime, no dependencies to install. Correctness is verified by
inspection and a handful of shell checks (directory presence, gitignore behavior,
no-real-secrets grep).

## Technical Context

**Language/Version**: N/A — Markdown documentation + TOML/INI-style config
examples + `.gitignore`. No programming language or compiled artifact.

**Primary Dependencies**: Git (version control), `mise` (secret rendering, per
the master plan — only its `.mise.toml` file format is referenced, not exercised
in this phase).

**Storage**: Files in the Git repository. No database.

**Testing**: Manual inspection plus scriptable shell checks (directory-existence
assertions, `git check-ignore` on the real secrets file, `grep` sweep proving no
real secret values are tracked). Documented in `quickstart.md`.

**Target Platform**: Any machine that can clone a Git repo; the eventual server
hosts are Debian, but Phase 0 has no host requirement.

**Project Type**: Infrastructure/documentation monorepo (single repository, one
directory per future Compose stack).

**Performance Goals**: N/A (no runtime). Human-comprehension goal: a newcomer
identifies each directory's purpose in under 5 minutes (SC-001).

**Constraints**: Zero real secret values in any tracked file (FR-013, SC-003);
repo must be understandable from static files with nothing running (FR-014,
SC-006); README structured so later phases append sections without rework.

**Scale/Scope**: One repository; ~4 top-level directories, ~4 root/docs files
created in this phase. Grows across 12 planned phases.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is an unpopulated
template — no ratified principles or gates are defined. There are therefore no
constitution gates to evaluate.

Applied instead as guiding principles from the master plan's design north star
(all satisfied by this plan):

- **Minimal custom code / off-the-shelf tools** — Phase 0 writes only docs and
  config examples; no code. ✅
- **Nothing silently goes outdated** — no pinned runtime, no build. ✅
- **Reproducible by a competent friend** — the entire deliverable is the
  self-documenting repo. ✅
- **Secrets never leak** — placeholder-example + gitignore pattern enforced. ✅

**Result**: PASS (no violations; Complexity Tracking not required).

## Project Structure

### Documentation (this feature)

```text
specs/001-repo-scaffolding/
├── plan.md              # This file (/speckit-plan command output)
├── spec.md              # Feature specification (/speckit-specify output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   ├── repo-structure.md    # Required directory/file layout contract
│   └── secrets-example.md   # Placeholder secrets-file contract
├── checklists/
│   └── requirements.md  # Spec quality checklist (/speckit-specify output)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created here)
```

### Source Code (repository root)

Phase 0 creates the repository skeleton itself. Target layout at the repo root:

```text
homeserve/                     # repo root (already contains PLAN.md)
├── PLAN.md                    # master plan (exists) — linked from README
├── README.md                  # NEW: self-documenting entry point + shareable report skeleton
├── .gitignore                 # NEW: ignores .mise.toml, .env, generated artifacts
├── .mise.toml.example         # NEW: placeholder-only secrets template
├── stacks/                    # NEW: one directory per Compose stack (empty + README)
│   └── README.md              #      explains "one dir per stack" convention
├── provision/                 # NEW: lean Ansible provisioning (empty + README)
│   └── README.md
├── komodo/                    # NEW: Komodo resource-sync definitions (empty + README)
│   └── README.md
└── docs/                      # NEW: documentation
    └── CONVENTIONS.md         # NEW: naming, ports, labels, "stateful → Dell", new-app checklist
```

**Structure Decision**: Single infrastructure monorepo. Each future Compose
stack gets its own directory under `stacks/`. `provision/`, `komodo/`, and
`docs/` mirror the master plan's §Phase 0 layout verbatim. Empty directories
carry a short `README.md` so their purpose is documented and Git tracks them.
No `src/`/`tests/` tree — there is no application code in this or the scaffolding
phase.

## Complexity Tracking

No constitution violations. This section intentionally left empty.
