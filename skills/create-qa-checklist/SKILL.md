---
name: create-qa-checklist
description: Create a product QA checklist and build-time test plan from a feature spec, before project ticket generation. Feeds create-project and orchestration, and works against any repo with a test suite. Use when asked for a QA checklist, a test plan for a spec, or the observable behaviors a feature must exhibit.
---

# Create QA Checklist

Create a QA checklist and implementation-facing test plan from a product or architecture spec.

**Usage:** `/create-qa-checklist <spec-file-path> [--out DIR] [--feature NAME] [--tickets TICKETS_FILE]`

**Default outputs:**
- `docs/plans/<feature-slug>-qa-checklist.md`
- `docs/plans/<feature-slug>-test-plan.md`

The output must be plain Markdown with concrete, verifiable acceptance checks. It should be useful to both Claude and Codex agents; avoid tool-specific directives except normal repo commands.

## Core Principle

Do not restate the implementation spec. Translate it into observable product behaviors and evidence-backed checks.

Good checklist items:
- "Memory is scoped by `user_id`, organization, and destination."
- "Deleted memory stops influencing future conversations."
- "A user can export generated data from a data-backed answer."

Weak checklist items:
- "Memory service is implemented."
- "Code follows best practices."
- "The feature works."

## Step 1 — Parse Arguments

Extract:
- Spec file path (required)
- `--out` output directory, default `docs/plans`
- `--feature` feature slug, default inferred from spec title or filename
- `--tickets` optional existing ticket/project breakdown file to augment

If the spec file does not exist or is empty, stop and ask for a valid file.

## Step 2 — Read Source Context

Read the spec. Identify:
- Product goals and user-visible behaviors
- System behaviors QA can verify through API/DB/logs
- Data persistence requirements
- Auth, security, and scoping requirements
- Background jobs, queues, cache behavior, or external integrations
- Rollout/default infrastructure assumptions
- Testing requirements already stated

If `--tickets` is provided, read it and map QA items to existing ticket names.

Inspect the repo briefly so the test plan matches its conventions:
- Look at the top-level test directory (`tests/`, `test/`, `spec/`, etc.) and any sub-structure (`tests/unit/`, `tests/integration/`, `tests/e2e/` — or whatever the repo actually uses).
- Note the test runner / harness (`pytest`, `jest`, `vitest`, `go test`, …).
- Note whether there is an existing browser/e2e harness (Playwright, Cypress, Selenium, repo-specific runner). Do not invent one if it is absent — fall back to manual QA recommendations.
- If the repo has `docs/plans/ai-orchestrator-ticket-spec.md`, read it: that file declares repo-specific verification conventions (login recipes, dev-server commands, screenshot paths) that this plan should align with.

## Step 3 — Create Product QA Checklist

Write `<feature-slug>-qa-checklist.md`.

Use this structure:

```markdown
# <Feature Name> QA Checklist

**Sources:**
- Tech spec: `<spec-path>`
- Product pitch: `<pitch-path>` _(omit this line if no pitch file is present)_

**Sibling artifact:** test plan at `<feature-slug>-test-plan.md`

This checklist defines product-level behaviors QA should verify before considering <feature> complete.

## Core User Behaviors

- [Behavior]
  - Verify: [exact user/API/browser action]
  - Expected: [observable outcome]
  - Evidence: [UI/API/DB/log/screenshot]

## Persistence And Data Integrity

...

## Scope, Auth, And Safety

...

## Operational Behavior

...

## Final Browser QA

...

## Completion Bar

The feature is product-complete when QA can demonstrate:
1. ...
```

Checklist rules:
- Prefer "A user/system should be able to..." phrasing.
- Every item needs a concrete verification method and expected evidence.
- Include negative cases: one-off instructions, unauthorized scope, deleted/failed states, invalid input, sensitive data.
- Include observability checks for DB rows/statuses when relevant.
- Keep it concise enough for humans to use.

## Step 4 — Create Build-Time Test Plan

Write `<feature-slug>-test-plan.md`.

Use this structure:

```markdown
# <Feature Name> Test Plan

**Sources:**
- Tech spec: `<spec-path>`
- Product pitch: `<pitch-path>` _(omit this line if no pitch file is present)_

**Sibling artifact:** QA checklist at `<feature-slug>-qa-checklist.md`

## Purpose

[Short statement tying tests to product risk.]

## Required Build-Time Tests

| Requirement | Test Type | Suggested Test | Ticket Mapping |
|---|---|---|---|
| [QA behavior] | unit / integration / e2e / visual | `tests/...` | [ticket or "create-project"] |

## Required Post-Build QA

| Requirement | Verification Path | Evidence |
|---|---|---|
| [QA behavior] | e2e / browser / manual | [artifact] |

## Ticket Injection Notes

[Copy/paste-ready bullets for create-project tickets.]
```

Test placement guidance (adapt to whatever the repo uses — do not impose a layout the repo does not have):
- **unit**: pure logic, serializers, prompt builders, validators, and narrow route/service behavior with mocked IO.
- **integration**: application integration that touches real boundaries (DB, FastAPI route via test client, queue, migration). If the repo distinguishes "with_deps" vs "no_deps" integration tiers, mirror that distinction; otherwise use whatever single tier exists.
- **e2e**: browser-facing flows using the repo's existing e2e harness. Prefer driving the live UI via Playwright MCP from a Claude/Codex session when the repo has no formal e2e harness and the work is one-off product QA.
- **visual**: screenshot capture for layout / design-language verification (e.g. `make visual`, Playwright `screenshot()`, or whatever the repo provides).
- **manual**: only when automation is not currently practical.

Browser/product QA guidance:
- Use the existing repo e2e harness and configuration for app URLs, auth, setup, teardown, and screenshots whenever one exists.
- Do not introduce a new browser test runner or environment convention unless the existing setup cannot support the scenario.
- If a feature needs new seed/reset/readiness behavior, add it to the e2e or integration harness rather than encoding operational startup details in this skill.
- When the repo's `docs/plans/ai-orchestrator-ticket-spec.md` defines a login recipe / dev server command, reference it instead of duplicating it.

## Step 5 — Map QA To Tickets

If tickets already exist, map each build-time test requirement to a ticket.

If tickets do not exist yet, write "create-project" in the Ticket Mapping column and produce a `## Ticket Injection Notes` section that `create-project` can use when generating tickets.

Ticket injection notes should be specific:

```markdown
- Ticket: Persist memory schema
  - Required tests: migration creates `user_memory_items`, `user_memory_events`, `user_memory_sources`.
  - Required DB assertions: events/items include `organization_id`, `user_id`, `destination`.

- Ticket: Wire memory into chat
  - Required tests: explicit user instruction creates memory proposal; later prompt receives active memory block.
```

## Step 6 — Summarize

After writing files, report:
- Checklist path
- Test plan path
- Highest-risk QA items
- Which tests should be implemented during orchestration
- Which checks remain final e2e/browser product QA

Do not create GitHub issues or run orchestration from this skill. It prepares QA artifacts for `create-project`, `orchestrate`, and final product QA.
