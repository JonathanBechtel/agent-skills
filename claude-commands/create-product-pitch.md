---
description: Generate a 1-page product pitch from a feature idea or existing tech spec, before any ticket work
argument-hint: <topic-or-spec-file> [--out DIR] [--feature NAME]
---

Generate a 1-page product pitch (problem, audience, hypothesis, core user flow, headline features, scope boundaries, success signal) from a feature idea or an existing tech spec. This is Step 1 of the orchestrator skill chain: pitch → spec → qa-checklist → project. Downstream skills consume the pitch for the "why" context they need to make judgment calls.

**Usage:** `/create-product-pitch <topic-or-spec-file> [--out DIR] [--feature NAME]`

**Arguments from `$ARGUMENTS`:**
- First positional argument: either a brief topic string ("consensus mock draft homepage") OR a path to an existing tech spec markdown file (required)
- `--out`: output directory (default: `docs/plans`)
- `--feature`: feature slug for the output file (default: inferred from topic or spec title)

**Instructions:**

Invoke the `create-product-pitch` skill and execute it end-to-end using `$ARGUMENTS`.

A pitch should be reviewable in under 2 minutes and fit on one printed page. Do not create tickets, write code, or perform QA from this command — those are downstream skills.
