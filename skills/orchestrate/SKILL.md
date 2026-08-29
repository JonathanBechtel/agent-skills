---
name: orchestrate
description: Run a GitHub Project's tickets to landed code - dependency DAG, integration waves, parallel agents, then the ship skill for PR, review rounds, merge, and deploy watch. Unattended by default. Use when asked to orchestrate a project, run a project's tickets, fan out tickets to agents, or continue an agent project.
metadata:
  short-description: Run a GitHub Project's tickets through to merged code
---

# /orchestrate — project to landed code

Execute every ticket in a GitHub Project, in dependency order, parallel where the DAG allows — then **land the work**. Orchestration is finished when the code is on the base branch and the deploy is green, not when the last agent returns.

You spawn agents, watch their output, and intervene when something goes wrong. You do **not** write ticket code yourself.

## Runtime adapters

Runtime-neutral. Use your runtime's primitive for each capability:

| Capability | Claude Code | Codex CLI |
|---|---|---|
| Invoke | `/orchestrate 8` | `$orchestrate 8` |
| Spawn a ticket agent | `Agent` tool, `mode: auto` | `spawn_agent` (requires `multi_agent = true` in `config.toml`) |
| Parallel fan-out | one message, multiple `Agent` calls, `run_in_background: true` | multiple `spawn_agent` calls, then `wait`; capped by `[agents] max_threads` (default 6) |
| Steer a running agent | follow-up message to the agent | `send_input` |
| Model per ticket | the ticket's `agent:` hint (`sonnet`/`opus`/`haiku`) | the hint has no Codex equivalent — use a matching definition in `.codex/agents/` if one exists, else inherit the session model and raise `model_reasoning_effort` to `high` for QA tickets |
| Tick / wait | `ScheduleWakeup` | `sleep <N>` inline |
| Task tracking | `TaskCreate` / `TaskUpdate` with `addBlockedBy` | the runtime's plan or todo mechanism; if it has none, keep an in-session ledger and print wave progress instead |

If your runtime cannot spawn sub-agents, **stop and say so**. Do not simulate parallel work by doing the tickets yourself in the main session — that defeats the context isolation the whole design rests on.

## Invocation

- `/orchestrate 8` — run project #8, inferring owner/repo from the current checkout
- `/orchestrate 8 --owner PearlEng --repo PearlEng/platform-ai`

## Arguments

- First positional argument: GitHub Project number (required)
- `--owner` — GitHub org/owner. Default: `gh repo view --json owner -q .owner.login`
- `--repo` — `owner/name`. Default: `gh repo view --json nameWithOwner -q .nameWithOwner`
- `--attended` — turn autonomy off: stop and ask at every decision the autonomy contract would otherwise let you make alone
- `--no-merge` — build and push, but never merge. Each wave ends at an open PR
- `--waves off` — force single-branch mode regardless of project size
- `--yes` — skip the execution-plan confirmation in Step 4

**Autonomous and merging by default** — stopping to ask costs a day, not a minute. The `ship` skill's **Autonomy contract** governs what may proceed alone and what must still hard-stop; read it there and apply it verbatim. `--attended` reverts to ask-first.

## Repo conventions take precedence

Before applying any default here, read the repo's own instructions: `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, and any per-repo orchestrator spec they point at (in DraftGuru, `docs/plans/ai-orchestrator-ticket-spec.md`). Repo rules win — test commands, conda env, branch naming, Definition of Done, browser-verification recipes.
---

## Procedure

Follow these steps in order. Do not skip or combine them.

### Step 1 — Parse arguments

Extract the project number and flags. Infer owner/repo from the checkout when not given.

### Step 2 — Fetch project tickets

1. List project items:
   ```bash
   gh project item-list <PROJECT_NUMBER> --owner <OWNER> --format json
   ```
2. For each item, fetch the issue:
   ```bash
   gh issue view <NUMBER> --repo <REPO> --json title,body,labels,state
   ```
3. Separate:
   - **Spec issue** (`type:spec`) — reference context, not executable work.
   - **Work tickets** (`status:open`) — executable units.
   - **Follow-up tickets** (`type:followup`) — filed by a previous run's review. Treat as ordinary work tickets if they're `status:open` and in the project.
4. Skip anything already `status:done`.

If `gh` is authenticated via a `GH_TOKEN` env var lacking the `project` scope, prefix project calls with `unset GH_TOKEN &&` so the keyring credential is used.

### Step 3 — Build the dependency DAG

Parse each ticket's `## Orchestrator Metadata` block:

- `depends-on: #123, #456` — upstream dependencies
- `agent: sonnet|opus|haiku` — model hint
- `wave: A` — integration wave (see Step 4). Optional; absent means "let the orchestrator decide"

Validate: every `depends-on` must resolve to an issue in the project, and the graph must be acyclic. On a cycle, stop and report.

Identify root tickets (no unmet dependencies), parallel groups (dependencies satisfied simultaneously **and** no overlapping files in "Files to change"), and the terminal QA ticket.

### Step 4 — Plan the waves

A **wave** is a batch of tickets integrated together: one branch, one PR, one review cycle, one merge. Waves keep feedback proportional to the work — fifteen tickets reviewed once at the end is reviewed too coarsely to catch anything early.

**Size gate — decide the mode:**

| Work tickets | Mode |
|---|---|
| ≤ 5 | **Single-wave.** One branch, one PR, ship and merge at the end. A small project doesn't need the ceremony. |
| > 5 | **Wave mode.** Each wave gets its own branch, PR, review cycle, and merge. |

`--waves off` forces single-wave mode.

**Deriving waves (wave mode only):**

1. **If tickets carry `wave:` metadata** — use it. That's the authored answer, cut at meaningful seams by whoever wrote the project.
2. **If they don't** — auto-chunk: walk the topological order and cut a wave every ~4 tickets, never splitting a parallel group and never placing a ticket before one it depends on.
3. **Validate either way:** every ticket's `depends-on` must land in the same wave or an earlier one. If authored metadata violates this, report the specific conflict and fall back to auto-chunking.
4. **The terminal QA ticket is always its own final wave.** It verifies integrated behavior, so it must run after everything else is on the base branch.

### Step 5 — Present the execution plan

Show, before doing anything:

```
Project: <name> (#<number>)   Mode: wave (9 tickets, 3 waves)   Autonomy: on

Wave A — feature/<slug>-wave-a
  Stage 1: #348 (sonnet)
  Stage 2: #349 (sonnet), #350 (sonnet)  [parallel]
  → ship --autonomous --merge → main → stage deploy

Wave B — feature/<slug>-wave-b
  Stage 1: #351 (sonnet)
  ...

Wave C — QA
  #356 (opus)
```

State plainly what will happen without further input: PRs opened, review rounds run, commits merged to main, follow-up tickets filed. Then ask **"Ready to start?"** and wait — unless `--yes`.

This is the last confirmation. Everything after it is designed to run while the user is away.

### Step 6 — Set up task tracking

One task per work ticket: subject `#<number> <title>`, a brief scope summary, and `addBlockedBy` dependencies matching the DAG. Group tasks by wave so progress reads as waves, not a flat list.
### Step 7 — Run the waves

For each wave, in order:

#### 7.1 Start from current base

```bash
git checkout main && git pull --ff-only
git checkout -b <type>/<project-slug>-wave-<x>
```

Every wave branches from **freshly pulled main**, so wave B develops against wave A as it actually landed, not as it was written.

In single-wave mode, do this once with a project-level branch name.

#### 7.2 Execute the wave's tickets

Process the wave's tickets in topological order.

**Sequential ticket (one ready):**
1. Mark the task `in_progress`.
2. Spawn one agent with the ticket's model hint and the prompt template below.
3. Wait for completion. Check for success signals: commit made, tests passed, label updated.
4. Mark the task `completed`.

**Parallel tickets (several ready, no file overlap):**

> **Non-overlapping files is NOT sufficient isolation.** The working tree, the git index, and the
> stash stack are shared. An agent told "don't edit these files" will still run repo-wide git
> commands, and a single `git stash` sweeps up a sibling's uncommitted work. This has cost real
> work — recovered only via `git fsck --unreachable` and an immediate rescue tag.
>
> **Parallel agents require separate worktrees.** In a shared worktree, run the stage
> **sequentially** even when the DAG permits parallelism. Sequential-and-correct beats
> parallel-and-lossy; the wall-clock saving is not worth the recovery.

1. Mark all `in_progress`.
2. Give each agent its own worktree, then spawn them all at once — one message with multiple `Agent` calls (Claude) or multiple `spawn_agent` calls then `wait` (Codex). Respect the concurrency cap.
3. As each returns, check its result and mark it `completed`.
4. Proceed only when the whole stage is done.

If separate worktrees are unavailable, collapse the stage to sequential and note it in the plan.

#### 7.3 Wave gate

Before shipping the wave, run the repo's own Definition of Done from `AGENTS.md`/`CLAUDE.md` — lint, format, full type check, the relevant test tiers, and any coverage or perf gate the repo enforces. Run it **once for the whole wave**, in the main session, not per ticket: agents check their own slice, and the thing that breaks is the seam between slices.

**Run the FULL test suite here, never a scoped subset.** A ticket agent's scoped run can be
green while the full suite is red — that is precisely the seam this gate exists to catch. On one
run a fix agent reported all-green from scoped tests while the full integration suite had four
failures, two of them in shared per-tick query budgets that no scoped selection would have
touched. If the gate is scoped, it is not a gate.

**Do not trust an agent's self-report in place of running the gate.** Agents die mid-run, and
several die during a redundant re-verification *after* their real work is sound. When an agent
fails but its work is staged and its own checks passed, prefer verifying the DoD yourself and
committing on its behalf over respawning and redoing the work.

If the gate fails: diagnose, and dispatch a fix agent scoped to the failure (still not writing the code yourself). Gate failures are ordinary work, not a stop condition. If the same gate fails after 3 fix attempts on the same root cause, that is hard-stop #2 in the autonomy contract.

#### 7.4 Ship the wave

Invoke the **`ship`** skill on the wave branch:

```
/ship --autonomous --merge          # Claude Code
$ship --autonomous --merge          # Codex CLI
```

(`--no-merge` if the user passed it; drop `--autonomous` under `--attended`.)

Ship owns everything from here: simplification pass, PR, review rounds, triage, thread resolution, squash merge, deploy watch. Do not duplicate its work or second-guess its triage. Hand it the wave's ticket numbers — its review budget (B.0) sizes on ticket count when it has one, commits otherwise.

**When ship returns:**
- **LANDED** → record the merge sha, the deploy result, and any follow-up tickets it filed. Continue to the next wave.
- **PAUSED / hard stop** → stop the orchestration. Do not start the next wave; it would branch from a main missing this one's code. Surface ship's notify-block, which waves landed, and which tickets remain.

#### 7.5 Fold in follow-up tickets

Ship may have filed `type:followup` issues during review. For each one:

- **Blocking for a later wave** — add it to that wave and re-validate the DAG. Rare; happens when review finds a shared assumption wrong.
- **Otherwise** — it stays out of this run, but it does not become somebody's someday. Ship files it already classified and labelled `agent:queued` (its B.4). Leave it queued. Step 10 releases the queue after the final wave lands, and the ones that qualified for `autonomy: auto` then drain themselves.

Never expand the current wave to absorb a follow-up. That is how a bounded run turns into an unbounded one.

That refusal was always right; what was missing was a drain on the other side. "The next session's work" is not a plan — the next session does not come, so the project cannot honestly be closed and the next one starts under the last one's debt. Holding to Step 10 keeps the run bounded **and** empties the tail, because orchestrate branches every wave from freshly pulled `main`: a follow-up merging mid-project moves the base under a wave that has not run.

### Step 8 — Handle agent failures

**First failure — retry once.** Read the agent's output, construct an improved prompt carrying the original ticket, what went wrong, and specific guidance to avoid it. Spawn a fresh agent.

**Before retrying, check whether the work is actually salvageable.** Agents frequently die *after*
doing sound work — stalled on a background wait, killed by a stream watchdog, or lost to an expired
session, often during a redundant re-verification pass. Run `git status` and `git log` first:

- **Work is staged/modified and the agent reported its own checks green** → do NOT respawn. Verify
  the repo's Definition of Done yourself in the main session, stage the agent's explicit paths, and
  commit on its behalf. Respawning discards an hour of correct work and re-rolls the dice.
- **Work is absent or incoherent** → retry with an improved prompt as below.
- **Work has vanished unexpectedly** → check `git reflog`, then
  `git fsck --unreachable | grep commit`, then sort candidates by date. Tag anything you recover
  *immediately* so GC cannot take it.

**Second failure — decide by mode:**

- **Attended:** report and ask — fix manually and resume, skip the ticket and continue with non-dependents, or abort.
- **Autonomous:** if the ticket has **no** dependents in this or any later wave, mark it `status:blocked`, file a `type:followup` issue carrying the failure and the agent's output, drop it from the wave, and continue. If it **does** have dependents, stop — everything downstream is built on it.

That is what lets an overnight run survive one bad ticket without shipping half a feature.

### Step 9 — Report progress

Keep it terse — 1–2 lines per ticket, never a dump of agent output. After each ticket: number, title, outcome, one key stat. After each wave: the merge sha, deploy status, and `[6/14 tickets · wave B of C]`.
### Step 10 — Final report

```markdown
## Orchestration Complete — <PROJECT_NAME> (#<NUMBER>)

**Mode:** wave (3 waves) · **Autonomy:** on · **Landed:** 3 of 3 waves

| Wave | Tickets | PR | Merged | Deploy |
|------|---------|----|--------|--------|
| A | #348–#350 | #601 | `abc1234` | green |
| B | #351–#354 | #602 | `def5678` | green |
| C (QA) | #356 | #603 | `9012abc` | green |

| Ticket | Title | Status | Notes |
|--------|-------|--------|-------|
| #348 | ... | Done | 42 tests added |

**Review:** 5 rounds across 3 PRs · 11 fixes · 4 skipped with reply

**Follow-up tickets — promoted** (released to `agent:auto`, will run unattended):
| # | Title | Why deferred |
|---|-------|--------------|
| #604 | ... | pre-existing, surfaced by review of #602 |

**Follow-up tickets — held** (still `agent:queued`, needs you):
| # | Title | Which axis failed |
|---|-------|-------------------|
| #605 | ... | verification: needs a visual check |

**Autonomous logic changes** (applied without asking — worth a look):
- #602 `a1b2c3d`: <one line>

**Not done:**
- <blocked or skipped tickets, with why>
```

Lead with what landed and what needs a human's eyes. The autonomous-changes list is the price of unattended merging — every judgment call made overnight, auditable in one screen.

#### Releasing the queue

Before writing the report, and **only after the final wave has merged and its deploy is green**, release the follow-ups held since 7.5:

```bash
gh issue edit <N> --repo <REPO> --remove-label "agent:queued" --add-label "agent:auto"
```

Promote only the ones ship classified `autonomy: auto`. Anything `assisted` or `manual` stays queued and goes in the held table — that is a human's call, not this run's.

**If any wave's deploy went red, promote nothing.** Base is broken; queueing more work onto it is the wrong move.

The two tables are the honest answer to "is this project closed?" The promoted list drains itself. The held list does not, and it is the only thing standing between this project and the next one.

---

## Important rules

- **Do NOT do the work yourself.** Coordinate agents. When one fails, diagnose and retry with a better prompt — don't start writing ticket code in the main session. The exception is the Step 7.3 wave gate, where you diagnose and dispatch.
- **Respect the DAG.** Never start a ticket before its dependencies have completed successfully.
- **Every wave branches from freshly pulled main.** Never stack a wave branch on the previous wave's branch.
- **Never start a wave after a failed one.** A failed ship means the base is missing code that later waves assume.
- **Keep the main context clean.** Extract pass/fail, commit sha, test counts from agent results; discard the rest.
- **Commit discipline.** Each ticket produces its own commit(s). The orchestrator never commits ticket code directly.
- **Label hygiene.** Each agent updates its own ticket to `status:done`. If one forgets, do it after confirming success. `status:done` records that an agent *finished*, not that the code landed — closure comes from the merge, via the `Closes #<n>` lines ship puts in the PR body. Do not close a ticket by hand at this point; the wave has not merged yet.
- **The autonomy contract is `ship`'s.** Don't invent a second set of stop conditions here. Read it there, apply it identically.
- **Bounded runs stay bounded.** Follow-up tickets get filed, never absorbed into the wave that found them.

## Agent prompt template

```
You are implementing ticket #<NUMBER> for the "<PROJECT_NAME>" project in the <REPO> repo.

## Your Task

<FULL ISSUE BODY>

## Prior Work

<For each completed upstream ticket, 3-5 bullets: what was built, key files created/modified,
key signatures. This is how the agent learns what is already in the codebase.>

<In wave mode, also note which earlier waves are already merged to main, so the agent knows
that code is on its base and does not rebuild it.>

## Execution rules — these are hard

- **Never start a background job, and never wait on one.** Run every command in the
  FOREGROUND with an explicit long timeout (e.g. `timeout: 900000`). Agents that park
  waiting on a background test run stall indefinitely and have to be rescued.
- **Never delegate to a sub-agent.** Do the work yourself.
- **Commit as soon as your own checks pass. Do NOT re-run suites to double-confirm.**
  The redundant second verification pass is where agents die mid-run and lose their report.
- **Never run `git stash`, `git reset`, `git checkout -- `, or `git restore`.** These are
  repo-wide and will destroy a concurrent agent's uncommitted work.
- **Stage explicit paths.** Never `git add -A` or `git add .`.
- If a check genuinely cannot pass, STOP and report which one and why. Do not commit around it.

## Instructions

1. Read every file listed in "Files to change" to understand current state.
2. Read any referenced spec or guide documents.
3. Implement the changes as specified.
4. Run the tests named in "Testing Requirements".
5. Run the repo's pre-commit / lint / type checks (see the repo's AGENTS.md or CLAUDE.md).
6. When everything passes, commit with a descriptive message. No Co-Authored-By lines,
   no AI attribution.
7. Update the issue label:
   gh issue edit <NUMBER> --repo <REPO> --remove-label "status:open" --add-label "status:done"

**Do not run repo-wide coverage** (`make coverage.diff` or equivalent). That is a wave-level
gate the orchestrator runs once; running it per ticket costs ~20 minutes each for a check
that is repeated anyway.
```

## Resuming

Orchestration is resumable. On re-invocation, Step 2 skips `status:done` tickets and Step 4 re-derives waves from what remains, so a run that stopped mid-project picks up at the first unlanded wave. Check `git log main` first to confirm which waves actually merged — ticket labels record that an agent finished, the merge record proves it landed.
