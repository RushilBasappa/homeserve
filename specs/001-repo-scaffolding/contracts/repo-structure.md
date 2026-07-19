# Contract: Repository Structure

The interface later phases and contributors rely on. A repository conforms to
Phase 0 if and only if all of the following hold.

## Required paths (relative to repo root)

| Path | Kind | Requirement |
|---|---|---|
| `PLAN.md` | file | Present; linked from `README.md`. |
| `README.md` | file | Present; states purpose + current phase; links `PLAN.md` and `docs/CONVENTIONS.md`; phase-aligned outline. |
| `.gitignore` | file | Ignores `.mise.toml`, `.env` / `*.env`, generated artifacts. |
| `.mise.toml.example` | file | Placeholder-only secrets template (see `secrets-example.md`). |
| `stacks/` | dir | Present with a `README.md` describing "one dir per Compose stack". |
| `provision/` | dir | Present with a `README.md`. |
| `komodo/` | dir | Present with a `README.md`. |
| `docs/` | dir | Present. |
| `docs/CONVENTIONS.md` | file | Naming, ports, routing labels, "stateful → Dell", new-app checklist. |

## Conformance checks (scriptable)

```sh
# All required directories exist
for d in stacks provision komodo docs; do test -d "$d" || echo "MISSING dir: $d"; done

# All required files exist
for f in PLAN.md README.md .gitignore .mise.toml.example docs/CONVENTIONS.md \
         stacks/README.md provision/README.md komodo/README.md; do
  test -f "$f" || echo "MISSING file: $f"
done

# README links the master plan and conventions
grep -q "PLAN.md" README.md || echo "README does not link PLAN.md"
grep -q "CONVENTIONS.md" README.md || echo "README does not link CONVENTIONS.md"
```

Any line of output indicates non-conformance.
