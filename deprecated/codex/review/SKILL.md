---
name: review
description: Slash-command style code review workflow. Invoke as /review (optionally with --files, --commit, and/or a spec path with optional #\"Section\"), to review for regressions, duplication, and spec compliance.
---

# /review

Run a structured code review for:
- regressions / breaking changes
- duplicated logic
- spec compliance (optional)

## Invocation

### Default (working tree)
- `/review`

Reviews staged + unstaged + untracked changes.

### Files/directories
- `/review --files app/services/ app/routes/news.py`

### Commit / range
- `/review --commit abc123`
- `/review --commit HEAD~3..HEAD`
- `/review --commit main..HEAD`

### Whole branch (common)
- `/review --branch`
- `/review --branch --base main`

### Spec compliance
- `/review docs/feature_spec.md`
- `/review 'docs/feature_spec.md#"Section Name"'`

You can combine a spec with `--files` or `--commit`.

## What to do (workflow)

### 1) Resolve scope (files + spec section)

Prefer the bundled scripts to make scope deterministic:
- Repo-local: `python .codex/skills/review/scripts/resolve_scope.py --help`
- Installed: `python "${CODEX_HOME:-~/.codex}/skills/review/scripts/resolve_scope.py" --help`

Then:
- If scope is empty, say so and ask the user what to review instead.
- Otherwise, review the diffs for those files (use `git diff` where applicable) and open the files.

### 2) Regression checks

Focus on “what could break”:
- removed/renamed symbols still referenced elsewhere
- changed function signatures / call sites
- config/env changes
- API contract changes (request/response schema, status codes)
- data model / migration changes

If reviewing a commit/working tree, inspect removals:
- `git diff --diff-filter=D --name-only`
- `git diff -U3` for key files

**Tests:** propose the smallest relevant set first. In this repo, good defaults are:
- `pytest -q` (defaults to `-m "not e2e"`)
- `pytest -q tests/unit`
- `pytest -q tests/integration` (if touching API/routes/DB)

If running tests might be slow or require infra, ask the user first.

### 3) Duplication scan

For notable new code (new functions/classes or large blocks):
- extract 2–5 “fingerprints”: function/class names, key strings, key branching conditions
- search for near-duplicates:
  - `rg -n "<fingerprint>" app tests`
  - `rg -n "def <name>" app`
- flag duplicates and suggest refactors only when it clearly reduces maintenance cost.

### 4) Spec compliance (when a spec path is provided)

1. Load the spec (or section) and extract requirements:
   - look for MUST/SHOULD/REQUIRED/acceptance criteria/edge cases
2. For each requirement, find the implementing code:
   - `rg -n "<endpoint|term|field|error message>" app tests`
3. Produce a gap analysis:
   - missing requirements
   - deviations (spec says X, code does Y)
   - scope creep (code not covered by spec)

For section extraction, you can use:
- Repo-local: `python .codex/skills/review/scripts/extract_spec_section.py --help`
- Installed: `python "${CODEX_HOME:-~/.codex}/skills/review/scripts/extract_spec_section.py" --help`

## Output format

Use this structure:

```markdown
## Review Summary
- **Scope**: (working tree | files | commit/range | spec)
- **Files reviewed**: N
- **Tests**: (not run | PASSED | FAILED: ...)

## Regressions
- [ ] Issue: ...
- [x] No regressions found

## Duplications
- [ ] ...
- [x] No significant duplications found

## Spec Compliance (if applicable)
### Implemented
- [x] Requirement: ... (file:line)

### Missing
- [ ] Requirement: ...

### Deviations
- [ ] Requirement: ...

## Recommendations
1. ...
```
