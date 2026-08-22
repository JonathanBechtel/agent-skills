---
name: create-project
description: Convert a spec document into a GitHub Project of orchestrator-ready tickets, carrying dependency metadata, model hints, and integration waves. Use when asked to turn a spec or plan into a GitHub Project, generate orchestrator tickets, or set up a project for agent execution.
metadata:
  short-description: Spec document to orchestrator-ready GitHub Project
---


Convert a spec document into a GitHub Project with orchestrator-ready tickets. Works against any repository that has a `gh` remote configured.

**Usage:** `/create-project <spec-file-path> [--owner OWNER] [--repo REPO] [--project-name NAME] [--model MODEL] [--qa-checklist QA_FILE] [--test-plan TEST_PLAN_FILE] [--conda-env ENV]`

**Arguments from `$ARGUMENTS`:**
- First positional argument: path to the spec markdown file (required)
- `--owner`: GitHub org/owner (default: inferred from the current repo's origin via `gh repo view --json owner -q .owner.login`)
- `--repo`: GitHub repo in `owner/name` form (default: inferred via `gh repo view --json nameWithOwner -q .nameWithOwner`)
- `--project-name`: Name for the GitHub Project (inferred from spec title if omitted)
- `--model`: Default agent model for tickets (default: `sonnet`)
- `--qa-checklist`: Optional QA checklist (typically from a `/create-qa-checklist` companion command)
- `--test-plan`: Optional build-time test plan
- `--conda-env`: Conda env name for the QA ticket's test commands (default: `$CONDA_DEFAULT_ENV` if set, otherwise inferred from `environment.yml` if present, otherwise leave a placeholder for the user to fill)

**Instructions:**

Follow these steps exactly. Do NOT skip steps or combine them.

---

### Step 1 — Parse arguments

Extract the spec file path and optional flags from `$ARGUMENTS`. Apply defaults for any missing flags:

- Owner / repo: run `gh repo view --json owner,name -q '.owner.login + "/" + .name'` from the project root and split into `OWNER` and `REPO`. If `gh` errors (not in a repo / no remote), prompt the user for explicit values.
- Conda env: try `$CONDA_DEFAULT_ENV`; if empty, inspect `environment.yml` for `name:`; if neither resolves, use `<CONDA_ENV>` as a placeholder and note it in the Step 9 summary.

### Step 2 — Read and validate the spec

Read the spec file. Verify it exists and contains meaningful content. Identify:
- The spec title (first `#` heading)
- Goals / non-goals
- Work breakdown or task list (if present)
- Any standards, conventions, or definitions of done mentioned

If the spec has no clear work breakdown section, note this — you'll need to decompose the work yourself in Step 3.

Also read upstream context artifacts when present (the full chain is: pitch → spec → qa-checklist → project):

**Product pitch** (`<spec-stem>-pitch.md` or `docs/plans/<spec-stem>-pitch.md`):
- Look for it adjacent to the spec or under `docs/plans/`.
- When found, extract the `## Headline Features`, `## Scope Boundaries`, `## Core User Flow`, and `## Success Signal` sections. These provide the "why" context for tickets and become the anchors for the QA gate's spec-compliance review.
- When missing AND the feature is novel/non-trivial, suggest the user run `/create-product-pitch` first — but do not block on it. A spec with no pitch is still actionable; the pitch is most valuable for features where scope/judgment calls matter.

**QA artifacts:**
- If `--qa-checklist` is provided, read that file.
- If `--test-plan` is provided, read that file.
- If either flag is omitted, look for adjacent defaults: `<spec-stem>-qa-checklist.md`, `<spec-stem>-test-plan.md`.

Use these artifacts as ticket requirements, not as optional background. Build-time tests from the test plan should be assigned to the tickets that implement the corresponding behavior. Product checklist items should appear in ticket definitions of done or in the final QA ticket when they require whole-feature validation.

If no QA artifacts exist (neither flag provided, no adjacent defaults), pause and recommend the user run `/create-qa-checklist <spec-file>` first before proceeding. QA artifacts substantially improve ticket quality — without them, the agent will infer verification requirements from the spec, which is strictly worse. Only continue without QA artifacts if the user explicitly says to.

If `docs/plans/ai-orchestrator-ticket-spec.md` exists in the current repo, read it for the canonical ticket structure AND for repo-specific verification recipes (login env vars, dev-server command, screenshot path, e2e harness). Treat anything in that file as authoritative for this repo; the templates in Step 7 below are fallbacks.

### Step 3 — Decompose into tickets

Break the spec into individual tickets. Each ticket should represent a **logical grouping of application work** that:

- **Coheres around a theme or feature slice.** Group related changes that an agent would naturally make together — e.g., "standardize all entity lookup endpoints" (touching 6 similar methods) is one ticket, not six. A model + its helpers + their tests can be one ticket if they're tightly coupled.
- **Fits within a single agent's context window.** The ticket description, project spec, upstream context, and the relevant code the agent needs to read/write should all fit comfortably. If an agent would need to hold too many files in mind at once, split the work.
- **Doesn't bleed into unrelated application areas.** A ticket that changes the data layer should not also require changes to the API layer unless they're inseparable. If completing a ticket reveals adjacent work is needed, that's a new ticket.

The goal is NOT "one class = one ticket" or "one test = one ticket." The goal is meaningful units of deliverable work that an agent can complete in one session without losing coherence.

For each ticket, determine:
1. A clear, imperative title (e.g., "Standardize entity lookup collection envelopes")
2. Which tickets it depends on (build the dependency chain)
3. Whether it can run in parallel with sibling tickets
4. Which QA / test-plan requirements belong to the ticket, if QA artifacts were provided
5. **Which verification flavors apply** (see "Verification flavor classification" below)

#### Verification flavor classification

Every ticket gets a `## Verification` section in its body listing which flavors apply. The flavors:

- **unit** — pure logic, no DB / HTTP / browser.
- **integration** — exercises real boundaries (DB, FastAPI/Django route via test client, queue, migration roundtrip). Most tickets get this.
- **e2e** — drive the live UI through a browser. Use `/verify` (the built-in skill) plus Playwright MCP when available, or the repo's existing e2e harness. May require a logged-in role.
- **visual** — capture and review screenshots for layout / design-language verification (`make visual`, Playwright screenshot, or repo equivalent).

Default matrix by ticket kind:

| Ticket kind | unit | integration | e2e | visual |
|---|---|---|---|---|
| Pure schema / migration | ✓ | ✓ (roundtrip) | — | — |
| Service / pure logic | ✓ | ✓ | — | — |
| API route (no UI) | optional | ✓ | — | — |
| Public UI page | — | ✓ | ✓ (anonymous) | ✓ |
| Admin / auth-gated UI | — | ✓ | ✓ (logged in) | ✓ |
| Cross-cutting refactor | ✓ | ✓ | — | — |
| QA gate | runs all | runs all | runs cross-ticket flow | refresh baseline |

Override the matrix when the spec demands it (e.g., a backend ticket that exposes a publicly-rendered HTML fragment may warrant a visual check). Tickets that involve a logged-in role MUST reference the repo's login recipe — see `docs/plans/ai-orchestrator-ticket-spec.md` for the recipe to copy; do not invent credentials.

#### File-overlap analysis

Before finalizing the ticket list, identify the **key files each ticket will modify**. Read the relevant source files to understand which tickets will touch the same files.

**Tickets that modify overlapping files must be sequenced as dependencies, not marked parallel.** Parallel tickets run in separate worktrees and merge independently — if two parallel tickets both modify the same file, the second merge will conflict, forcing a costly re-run.

When presenting the ticket list, annotate each ticket with its primary files. If you discover overlap between tickets that would otherwise be parallel, add a dependency edge to serialize them.

#### Horizontal migration tickets — flag and budget up front, do not split

Some tickets change one small thing — a function signature, an injected dependency, an auth contract — but the test suite forces fixture edits across many files. These are **horizontal migrations**: small logical change, wide test-file fan-out.

**Do not split horizontal migration tickets.** You cannot commit partial test-suite updates — the test suite won't pass until all affected fixtures are migrated together, and the orchestrator requires each ticket to land as a clean commit with green tests. A split would leave at least one sub-ticket whose branch cannot be merged because the test suite is half-migrated. The only way to keep tests green is to land the whole fan-out in one commit, which means one ticket.

**How to spot them at decompose time:**
- The change swaps a shared dependency, renames a widely-imported symbol, or alters a signature that appears in many test fixtures/mocks.
- Spec language like "migrate X contract," "replace Y dependency," "rename Z everywhere."
- A single module change forces mock/override updates across 5+ test files. When in doubt, `grep -rl` the symbol being changed — if there are >5 hits in `tests/`, it's horizontal.

**How to handle them:**
1. Keep the ticket whole — do not split.
2. In the ticket's `## Notes for orchestrator` section (add one if not present), flag it explicitly:
   > This is a horizontal migration. Expected wide test-fixture fan-out. Recommend running the orchestrator with `--max-turns 150` (or higher) for this project.
3. In the Step 9 summary, include `--max-turns 150` in the recommended orchestrator invocation when any horizontal migration ticket exists in the project.

The default 50-turn budget is tuned for vertical tickets. Horizontal migrations routinely burn 80–150 turns because they're mechanical file-by-file fixture edits — turns spent on discovery and repetition, not thinking. Raising the budget is the fix, not splitting.

**Ask the user to confirm or adjust the ticket list before proceeding.** Do NOT create any GitHub resources until the user approves.

### Step 3.5 — Assign integration waves

The orchestrator integrates a project in **waves**: a batch of tickets sharing one branch, one PR, one review cycle, one merge. Waves keep review feedback proportional to the work — fourteen tickets reviewed once at the end is reviewed too coarsely to catch anything while it's cheap to fix.

Projects of **5 tickets or fewer** don't need waves; the orchestrator runs them as a single branch. Emit `wave:` anyway (all `A`) so the metadata is uniform.

For larger projects, assign each ticket a `wave:` letter (`A`, `B`, `C`, …) by these rules:

1. **Cut at seams, not at counts.** A wave should merge to main on its own and leave the app working: schema + migration; then the service layer over it; then routes and UI; then QA. Prefer a seam where the next wave genuinely depends on the previous having landed.
2. **Target 3–5 tickets per wave.** Fewer than 3 is CI overhead; more than 5 and the review surface is coarse again.
3. **Dependencies never point forward.** Every ticket's `depends-on` must resolve to a ticket in the same wave or an earlier one. This is a hard constraint — the orchestrator validates it and falls back to auto-chunking if it's violated.
4. **Parallel groups stay together.** Tickets that can run concurrently belong in the same wave.
5. **The QA ticket is always the final wave, alone.** It verifies integrated behavior across everything that landed before it.

Show the wave grouping with the ticket list in Step 3 and let the user re-cut it — they know the meaningful seams better than the DAG does.

If a project has no seam — every ticket in the same module, nothing landing independently — say so and assign one wave. A forced boundary that breaks main is worse than a coarse review.

### Step 4 — Ensure labels exist

Before creating any issues, verify the required labels exist:

```bash
gh label create "status:open" --color "0E8A16" --description "Ticket is open and available" --repo <REPO> --force
gh label create "type:spec" --color "C5DEF5" --description "Project spec, not actionable work" --repo <REPO> --force
gh label create "type:followup" --color "FBCA04" --description "Filed by review; out of scope for the PR that surfaced it" --repo <REPO> --force
```

### Step 5 — Create the GitHub Project

After user approval, create the GitHub Project:

```bash
gh project create --owner <OWNER> --title "<PROJECT_NAME>" --format json
```

Save the project number from the output.

### Step 6 — Create the master spec issue

Create a GitHub Issue tagged `type:spec` containing:
- A "Product context" preamble pulled from the pitch (when present): elevator description, headline features, scope boundaries. Skip when no pitch exists.
- A "Related artifacts" section linking every upstream file by relative path. Omit lines for artifacts that don't exist — never link a missing file:

  ```markdown
  ## Related artifacts

  - Tech spec: `<spec-path>`
  - Product pitch: `<pitch-path>`
  - QA checklist: `<qa-checklist-path>`
  - Test plan: `<test-plan-path>`
  ```

- The full spec content (or a summary + link to the in-repo file)
- A work breakdown listing all child tickets
- General definition of done and testing requirements from the spec

```bash
gh issue create --repo <REPO> --title "Project Spec: <PROJECT_NAME>" --label "type:spec" --body "<BODY>"
```

Save the spec issue number. Add it to the project:
```bash
gh project item-add <PROJECT_NUMBER> --owner <OWNER> --url <ISSUE_URL>
```

### Step 7 — Create work tickets

For each ticket from Step 3, create a GitHub Issue following the template below.

**Important sequencing:** Create tickets in dependency order (roots first) so that `depends-on` references can use real issue numbers. After creating each ticket:

1. Create the issue: `gh issue create --repo <REPO> --title "<TITLE>" --label "status:open" --body "<BODY>"`
2. Save the issue number
3. Add to the project: `gh project item-add <PROJECT_NUMBER> --owner <OWNER> --url <ISSUE_URL>`

#### Ticket template

```markdown
## Overview

[What this ticket does — 1-3 sentences.]

## Scope

[If the ticket covers multiple items (endpoints, models, methods), list them explicitly.]

## Implementation Guide

### Files to change

- `path/to/file.py` — [Brief description of what changes in this file.]
- `path/to/other.py` — [Brief description.]
- `tests/unit/test_file.py` — [New or modified tests.]

### Code pattern to follow

[Reference an existing implementation that this ticket should mirror. Point to a specific function, class, or file that serves as the model. If a sibling ticket has already been completed and can serve as a reference, call it out.]

### Expected signatures / contracts

[Specify the exact function signatures, return types, or interface contracts the ticket must produce. When changing an existing interface, show before and after.]

## Project Context

- Master reference: #<SPEC_ISSUE_NUMBER>
- Local spec: `<SPEC_FILE_PATH>`
- Product pitch: `<PITCH_PATH>` _(omit this line if no pitch file exists)_
- QA checklist: `<QA_CHECKLIST_PATH>` _(omit if not present)_
- Test plan: `<TEST_PLAN_PATH>` _(omit if not present)_

## Definition of Done

- [Specific, verifiable criterion. State what the output looks like, not "works correctly."]
- [Another criterion.]

## Verification

**Flavors that apply:** [list any of: unit, integration, e2e, visual — match the matrix from Step 3]

### Unit tests
- [What pure-logic tests to write, or `N/A` if this flavor doesn't apply.]

### Integration tests
- [Routes / DB / migration tests with concrete file paths under the repo's test directory.]
- [Any build-time QA requirements from the test plan mapped to this ticket.]

### Browser end-to-end
*Only present when the e2e flavor applies. Otherwise omit this subsection entirely.*

**Role:** [admin / staff / anonymous]

**Login recipe:** [Reference the recipe in `docs/plans/ai-orchestrator-ticket-spec.md` by name — e.g. "Use the admin login recipe (env vars `<REPO>_ADMIN_EMAIL` / `<REPO>_ADMIN_PASSWORD`)." Do not duplicate credentials here. Omit this line when Role is anonymous.]

**Workflow steps:**
1. [`browser_navigate` → URL]
2. [`browser_snapshot` → assert observable state]
3. ...

**Evidence to capture (via `browser_take_screenshot`):**
- `<screenshot-name>.png`

The implementing agent should invoke `/verify` to drive the live app, using Playwright MCP when available or the repo's e2e harness otherwise.

### Visual
*Only present when the visual flavor applies. Otherwise omit.*

- Capture screenshots via the repo's visual harness (e.g. `make visual`). Read them back and confirm layout / design-language fidelity.

## Product QA Mapping

- [Checklist item(s) from the QA artifacts that this ticket helps satisfy, if any.]
- [Evidence expected after implementation.]

## Dependencies

- [Human-readable upstream ticket descriptions]

## Successors

- [Human-readable downstream ticket descriptions]

## Orchestrator Metadata

- depends-on: #<ISSUE_NUMBER>, #<ISSUE_NUMBER>
- agent: <MODEL>
- wave: <WAVE_LETTER>
```

#### Example: Foundation ticket

```markdown
## Overview

Refine `<package>/helpers.py` so collection-style and singular-style endpoints can parse provider payloads into standard envelopes through reusable helpers.

## Implementation Guide

### Files to change

- `<package>/helpers.py` — Add `parse_collection_response()` and `parse_singular_response()` helpers.
- `tests/unit/<package>/test_helpers.py` — New tests for both helpers.

### Code pattern to follow

Follow the existing `_extract_items()` helper in `<package>/helpers.py` for payload traversal. The new helpers wrap that extraction with envelope construction.

### Expected signatures / contracts

```python
def parse_collection_response(
    raw: dict, item_schema: type[T], key: str
) -> CollectionResponse[T]:

def parse_singular_response(
    raw: dict, item_schema: type[T]
) -> SingularResponse[T]:
```

## Project Context

- Master reference: #<SPEC_ISSUE>
- Local spec: `<SPEC_FILE_PATH>`
- QA checklist: `docs/plans/<feature-slug>-qa-checklist.md`
- Test plan: `docs/plans/<feature-slug>-test-plan.md`

## Definition of Done

- Shared helpers exist for collection and singular parsing.
- Helpers can support the endpoint migrations in later tickets.

## Verification

**Flavors that apply:** unit, integration

### Unit tests
- `tests/unit/<package>/test_helpers.py` — parsing behavior for both helpers across happy paths and malformed payloads.

### Integration tests
- Focused adapter test that exercises at least one collection case and one singular case through `parse_collection_response()` / `parse_singular_response()`.

## Dependencies

- Convert <package> models into a models/ package
- Add standard <package> envelope primitives

## Successors

- All endpoint standardization tickets

## Orchestrator Metadata

- depends-on: #<UPSTREAM_1>, #<UPSTREAM_2>
- agent: sonnet
- wave: <WAVE_LETTER>
```

#### Example: Grouped application ticket

```markdown
## Overview

Standardize all entity and lookup endpoints onto the collection response envelope.

## Scope

- `list_regions`
- `list_programs`
- `lookup_districts`
- `lookup_schools`
- `search_users_detailed`
- `list_student_groups`

## Implementation Guide

### Files to change

- `<package>/adapter.py` — Update 6 methods to use `parse_collection_response()` and return `CollectionResponse[...]`.
- `<package>/models/entities.py` — Add any missing Pydantic schemas for entity items.
- `tests/unit/<package>/test_adapter.py` — Update entity adapter tests.

### Code pattern to follow

Follow the pattern from #<PRIOR_TICKET> (survey list standardization) — that ticket already converted `list_surveys` using the same helpers. Mirror its approach: replace raw dict handling with `parse_collection_response()`, update the return annotation, update tests.

### Expected signatures / contracts

```python
# Before (all 6 methods follow this pattern)
def list_regions(self, token: str) -> list[dict]:

# After
def list_regions(self, token: str) -> CollectionResponse[RegionSchema]:
```

## Project Context

- Master reference: #<SPEC_ISSUE>
- Local spec: `<SPEC_FILE_PATH>`
- QA checklist: `docs/plans/<feature-slug>-qa-checklist.md`
- Test plan: `docs/plans/<feature-slug>-test-plan.md`

## Definition of Done

- All targeted entity endpoints return `CollectionResponse[...]`.
- Existing list and tuple variants are removed from the adapter boundary.

## Verification

**Flavors that apply:** unit, integration

### Unit tests
- `tests/unit/<package>/test_adapter.py` — coverage for each migrated method, including the envelope shape and at least one error path.

### Integration tests
- Lookup tool and template tests that consume these adapter methods downstream.

## Dependencies

- Add standard <package> envelope primitives
- Add adapter helpers for standard collection and item parsing

## Successors

- Downstream cleanup that can rely on entity collection standardization

## Orchestrator Metadata

- depends-on: #<UPSTREAM_1>, #<UPSTREAM_2>
- agent: sonnet
- wave: <WAVE_LETTER>
```

### Step 8 — Create QA ticket

After all work tickets are created, append a final **QA ticket** that gates the project before the orchestrator creates the final PR. This ticket is always the last one and depends on every work ticket.

Substitute the project's conda env name (resolved in Step 1) into the test commands below. If no env was resolved, leave `<CONDA_ENV>` as a placeholder and note it in the Step 9 summary.

Create the QA ticket using `gh issue create` with the following template:

```markdown
## Overview

Final quality gate for the project. Run the full test suite on the feature branch after all work tickets have merged, fix any cross-ticket regressions, and perform a holistic review of the combined work against the original spec.

This ticket has five jobs:
1. **Green CI** — every test passes, pre-commit is clean.
2. **Regression fixes** — resolve interface mismatches, import errors, type conflicts, or test failures that only surface when independently-developed changes combine.
3. **Test-effectiveness audit** — confirm the green suite actually tests what it claims. Tests written across many tickets are prone to passing while testing nothing (the classic case: an integration test that mocks the very dependency it exists to exercise, so a real defect ships behind green CI).
4. **Spec compliance and quality review** — compare the final feature branch against the project spec. Look for gaps in coverage, architectural issues, potential bugs, and opportunities to improve the overall quality of the delivered work.
5. **Product QA readiness** — confirm all build-time QA / test-plan requirements are implemented or explicitly documented as final e2e / browser / manual QA.

## Implementation Guide

### Phase 1 — Full test suite

1. Run the full test suite:
   `conda run -n <CONDA_ENV> --no-capture-output python -m pytest tests/ -x`
2. Run pre-commit on all files:
   `conda run -n <CONDA_ENV> --no-capture-output pre-commit run --all-files`
3. Fix any failures. Common cross-ticket regressions:
   - Import errors from renamed/moved symbols across ticket boundaries
   - Type mismatches where one ticket changed a return type another ticket depends on
   - Test fixtures that became stale after upstream changes
   - Merge artifacts (duplicate imports, conflicting constants)
4. Re-run until clean.

### Phase 1.5 — Test-effectiveness audit

A green suite is the *precondition* for this check, not the conclusion. Across a multi-ticket project the highest-risk defect is a test that passes while testing nothing — most dangerously an integration test that mocks the dependency (DB, cache, external service) it exists to exercise, letting a real failure ship behind green CI.

1. Dispatch the `test-quality-auditor` agent (Agent tool, `subagent_type: test-quality-auditor`) over the full feature diff — point it at `git diff main...HEAD -- tests/` plus the code those tests cover. If that agent is not registered in this environment, run the same audit inline against its checklist (mocked-subject, assertion theater, can't-fail tests, wrong-tier placement, fixture duplication).
2. Treat **Critical** findings as blocking — fix before the gate passes:
   - A test that mocks the exact dependency/function it claims to verify.
   - An integration test that never touches the real service it is meant to exercise (mock it out and it belongs in the mocked tier instead).
   - A test that would still pass if the implementation were deleted or inverted.
3. Treat **Major/Minor** findings (assertion theater, misplaced tier, duplicated fixtures instead of shared helpers/factories) as fix-or-document.

### Phase 2 — Spec compliance and quality review

1. Read the project spec (master reference issue + local spec file).
2. Read any QA checklist / test plan referenced by the project.
3. Run `git diff main...HEAD` to see the full set of changes on the feature branch.
4. Evaluate the delivered work against the spec and QA artifacts:
   - **Coverage gaps:** Are there spec requirements that weren't implemented or were only partially addressed?
   - **Headline feature delivery** (when a pitch is present): Walk through the pitch's `## Headline Features` list. For each headline feature, point at the specific code/UI that delivers it. If any headline feature is undeliverable from the merged work, that's a coverage gap.
   - **Scope creep check** (when a pitch is present): Walk through the pitch's `## Scope Boundaries`. If any "not doing" item was secretly built, flag it and decide whether to keep, gate behind a flag, or revert.
   - **QA / test gaps:** Are there build-time QA items that were not covered by tests?
   - **Architectural quality:** Do the changes follow existing patterns consistently? Are there inconsistencies across tickets where different agents made different choices?
   - **Potential bugs:** Look for edge cases, missing error handling at boundaries, or logic that doesn't match the spec's intent.
   - **Dead code / unnecessary artifacts:** Did any ticket leave behind scaffolding, unused imports, or commented-out code?
5. Fix any issues found. For anything too large to fix in this ticket, leave a clearly documented TODO with a brief explanation.

### Phase 3 — Browser end-to-end verification

Invoke `/verify` to drive the live app via the available browser tooling (Playwright MCP when installed, the repo's e2e harness otherwise). Then:

1. **Run each per-ticket Browser end-to-end recipe** from the work tickets that declared the `e2e` flavor. The recipes are self-contained — follow them ticket by ticket and capture the listed evidence.
2. **Run one cross-ticket end-to-end flow** that exercises the seam where independently-developed tickets meet. The exact flow depends on the project, but at minimum it should:
   - Touch any logged-in workflow once (using the repo's login recipe from `docs/plans/ai-orchestrator-ticket-spec.md`).
   - Walk from data-creation → propagation → public-surface visibility, so that a change made through one ticket's surface is visible through another ticket's surface.
   - Compare a "before" and "after" screenshot of any page where consensus / aggregate / derived state should change.
3. **Refresh the visual baseline.** Run the repo's static screenshot capture once (`make visual` or equivalent) to update the checked-in baseline.

If any browser verification surfaces a regression, file it as a Phase 1 fix and re-run.

### Files to change

Cannot be determined in advance — depends on which regressions and quality issues surface.

## Project Context

- Master reference: #<SPEC_ISSUE_NUMBER>
- Local spec: `<SPEC_FILE_PATH>`
- Product pitch: `<PITCH_PATH>` _(omit if not present)_
- QA checklist: `<QA_CHECKLIST_PATH>` _(omit if not present)_
- Test plan: `<TEST_PLAN_PATH>` _(omit if not present)_

## Definition of Done

- Full test suite passes.
- Pre-commit passes on all files.
- Test-effectiveness audit passed — no Critical `test-quality-auditor` findings (mocked-subject tests, integration tests that don't hit the real service, tests that can't fail).
- No regressions from the pre-project baseline.
- Spec compliance review completed — all requirements addressed or gaps documented.
- No architectural inconsistencies across the combined work.

## Verification

**Flavors that apply:** unit, integration, e2e, visual (all four — this ticket runs the full sweep)

### Unit + integration
- Run `python -m pytest tests/` (or repo equivalent) — all tests must pass.
- Run `pre-commit run --all-files` — must pass clean.

### Browser end-to-end
- Execute every per-ticket Browser end-to-end recipe from the project's work tickets, plus the cross-ticket flow described in Phase 3.

### Visual
- Refresh the repo's screenshot baseline (e.g. `make visual`) and visually review the new PNGs.

## Dependencies

- [All work tickets]

## Successors

- None — this is the final gate.

## Orchestrator Metadata

- depends-on: #<ALL_WORK_TICKET_NUMBERS>
- agent: opus
- wave: <FINAL_WAVE_LETTER>
```

**Important:** The QA ticket must use `agent: opus` because it requires synthesizing the work of all prior tickets, evaluating spec compliance, diagnosing cross-cutting failures, and making judgment calls about architectural quality across the full scope of the project.

### Step 9 — Summary

After all tickets are created, present a summary:
- Project name and number
- Spec issue number and URL
- Table of all created tickets with their numbers, titles, dependencies, and URLs
- The dependency graph showing execution order and what can run in parallel
- The command to run the orchestrator against this project:

```bash
python -m scripts.orchestrator \
  --project <PROJECT_NUMBER> \
  --owner <OWNER> \
  --repo <REPO> \
  --feature-branch feature/<BRANCH_NAME> \
  --max-parallel 3 \
  --dry-run
```

Notes:
- If the current repo doesn't have `scripts/orchestrator`, swap in whatever orchestrator runner the project uses (a `make orchestrate` target, a different entrypoint, etc.).
- If any ticket in the project was flagged as a horizontal migration in Step 3, add `--max-turns 150` to the command above.
- If `<CONDA_ENV>` was left as a placeholder in Step 8 (no env could be auto-detected), flag this so the user fills it in before running the orchestrator.
