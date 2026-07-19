# Quickstart & Validation: Phase 0 — Foundation & Repo Scaffolding

This guide validates that the scaffolding is complete and correct. There is
nothing to build or run — validation is inspection plus a few shell checks.

## Prerequisites

- A clone of the repository.
- Git and a POSIX shell available.

## Setup

```sh
cd homeserve   # repo root
```

## Validation scenarios

### 1. Repo is self-documenting (User Story 1 / SC-001)

```sh
ls -1                      # expect: PLAN.md README.md .gitignore .mise.toml.example stacks provision komodo docs
cat README.md             # expect: purpose, current phase status, links to PLAN.md and docs/CONVENTIONS.md
```

**Expected**: Each top-level directory's purpose is understandable within
5 minutes from the README + directory READMEs. See
[contracts/repo-structure.md](./contracts/repo-structure.md) for the full check.

### 2. Structure conformance (FR-001..FR-005, FR-012)

Run the scriptable checks in
[contracts/repo-structure.md](./contracts/repo-structure.md). **Expected**: no
output (all paths present, README links resolve).

### 3. Secrets are safe (User Story 2 / SC-002..SC-004)

```sh
cat .mise.toml.example                 # expect: placeholders only, one per required secret
cp .mise.toml.example .mise.toml       # create the real file from the template
git check-ignore -q .mise.toml && echo "IGNORED OK" || echo "NOT IGNORED — FAIL"
git status --porcelain | grep -q '.mise.toml$' && echo "STAGED — FAIL" || echo "not staged — OK"
```

**Expected**: `.mise.toml.example` lists every plan secret as a placeholder;
`.mise.toml` is `IGNORED OK` and `not staged`. See
[contracts/secrets-example.md](./contracts/secrets-example.md).

### 4. No real secret is tracked (FR-013 / SC-003)

Manually review every tracked file; confirm each secret value reads as a
placeholder. Optional sweep for obviously-real tokens:

```sh
git ls-files | xargs grep -nEi 'api[_-]?key|token|secret|password' 2>/dev/null
```

**Expected**: every match is a placeholder or a documentation reference — no real
credential.

### 5. Conventions are followable (User Story 3 / SC-005)

```sh
cat docs/CONVENTIONS.md   # expect: naming, ports, routing labels, "stateful → Dell", new-app checklist
```

**Expected**: A contributor can describe naming, data placement, and the add-an-app
steps for a hypothetical app using only this document.

## Done when

- All checks in scenarios 1–3 pass with expected output.
- Scenario 4 review finds zero real secrets.
- Scenario 5 confirms the conventions doc is self-sufficient.

Mapping of scenarios → requirements lives in
[data-model.md](./data-model.md); implementation steps are produced by
`/speckit-tasks` into `tasks.md`.
