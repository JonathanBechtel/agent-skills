---
description: Create a product QA checklist and build-time test plan from a feature spec, before project ticket generation
argument-hint: <spec-file-path> [--out DIR] [--feature NAME] [--tickets TICKETS_FILE]
---

Create a product QA checklist and build-time test plan from a feature spec, before project ticket generation. Works against any repository; outputs are plain Markdown intended to be read by Claude, Codex, or humans.

**Usage:** `/create-qa-checklist <spec-file-path> [--out DIR] [--feature NAME] [--tickets TICKETS_FILE]`

**Arguments from `$ARGUMENTS`:**
- First positional argument: path to the spec markdown file (required)
- `--out`: output directory (default: `docs/plans`)
- `--feature`: feature slug/name for output files (default: inferred from spec title or filename)
- `--tickets`: optional existing ticket/project breakdown file to augment

**Instructions:**

Invoke the `create-qa-checklist` skill and execute it end-to-end using `$ARGUMENTS`.

Do not create GitHub issues, run orchestration, or perform final browser QA from this command. This command prepares QA artifacts that `/create-project` consumes via its `--qa-checklist` and `--test-plan` flags.
