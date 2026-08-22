---
name: orchestrate-cli
description: Run a GitHub Project through the scripts/orchestrator CLI. Thin wrapper that builds the command, previews the plan with --dry-run, then executes. The orchestrator handles DAG resolution, branching, worktrees, parallel agents, retries, merge conflicts, and PR creation.
when-to-use: When the user wants to run the CLI orchestrator, or says "run orchestrator-cli", "run the orchestrator script", or "orchestrate-cli".
argument-hint: "<project-number> [--max-parallel N] [--feature-branch NAME] [--dry-run] [flags...]"
user-invocable: true
---

# /orchestrate-cli — Run the orchestrator CLI

Wrapper around `python -m scripts.orchestrator` that infers defaults, previews the plan, and executes.

The orchestrator package (`scripts/orchestrator/`) handles everything: GitHub ticket fetching, DAG resolution, branch/worktree management, parallel `claude -p` subprocess agents, retry/recovery, merge conflict resolution, and final PR creation. This skill just makes it easy to invoke.

## Invocation

- `/orchestrate-cli 8` — run project #8 with defaults
- `/orchestrate-cli 8 --max-parallel 3` — run with 3 concurrent agents
- `/orchestrate-cli 8 --dry-run` — preview only, no execution
- `/orchestrate-cli 8 --feature-branch feature/my-feature --max-parallel 2`

## Arguments

- First positional argument: GitHub Project number (required)
- All remaining flags are passed directly to the orchestrator CLI
- Common flags: `--max-parallel`, `--feature-branch`, `--model`, `--max-retries`, `--on-failure`, `--dry-run`

---

## Procedure

### Step 1 — Parse arguments and infer defaults

Extract the project number from the first positional argument. All other flags pass through to the CLI.

Infer defaults from the current repo state:
- **`--owner`**: Parse from `git remote get-url origin` (e.g., `PearlEng` from `github.com/PearlEng/platform-ai.git`)
- **`--repo`**: Parse from `git remote get-url origin` (e.g., `PearlEng/platform-ai`)
- **`--feature-branch`**: If the user is already on a non-main branch, offer to use it. Otherwise, infer from the project name.
- **`--base-branch`**: Default to `main`

### Step 2 — Pre-flight checks

Before running, verify:

1. **Working tree is clean:**
   ```bash
   git status --porcelain
   ```
   If dirty, tell the user to commit or stash first. Do NOT proceed with a dirty tree.

2. **Orchestrator package exists:**
   ```bash
   ls scripts/orchestrator/__main__.py
   ```
   If missing, the user is not in the right repo.

3. **Project exists and has tickets:**
   ```bash
   gh project item-list <PROJECT_NUMBER> --owner <OWNER> --format json --limit 1
   ```

4. **conda environment is available:**
   ```bash
   conda run -n platform-ai --no-capture-output python -c "import scripts.orchestrator"
   ```

If any check fails, report the issue clearly and stop.

### Step 3 — Dry run preview

Always run a dry-run first so the user can see the execution plan:

```bash
conda run -n platform-ai --no-capture-output python -m scripts.orchestrator \
  --project <PROJECT_NUMBER> \
  --owner <OWNER> \
  --repo <REPO> \
  --feature-branch <FEATURE_BRANCH> \
  --base-branch <BASE_BRANCH> \
  <USER_FLAGS> \
  --dry-run \
  --verbose
```

Present the output to the user. It will show:
- Tickets found and their dependency order
- The DAG visualization
- Which tickets would run in parallel
- Which tickets are already done (skipped)

Ask: **"Ready to execute?"** — wait for confirmation.

### Step 4 — Execute

Run the orchestrator for real. Use `run_in_background: true` on the Bash tool so the process runs without blocking the conversation:

```bash
conda run -n platform-ai --no-capture-output python -m scripts.orchestrator \
  --project <PROJECT_NUMBER> \
  --owner <OWNER> \
  --repo <REPO> \
  --feature-branch <FEATURE_BRANCH> \
  --base-branch <BASE_BRANCH> \
  <USER_FLAGS> \
  --verbose 2>&1 | tee /tmp/orchestrator-<PROJECT_NUMBER>.log
```

The orchestrator streams progress via its own logging:
- `[INFO]` lines show ticket starts, agent tool calls, session completion
- `[WARNING]` lines show retries and failures
- `[ERROR]` lines show blocking issues

### Step 5 — Monitor and intervene

While the orchestrator runs:
- Periodically check the log for progress: `tail -20 /tmp/orchestrator-<PROJECT_NUMBER>.log`
- If the orchestrator exits with code 0: all tickets succeeded.
- If it exits with code 1: at least one ticket failed.

When the orchestrator stops (either success or `--on-failure stop`):
1. Read the log tail to identify what happened.
2. Report the summary to the user.
3. If there was a failure, show the relevant log section and ask how to proceed.

### Step 6 — Post-run summary

After the orchestrator finishes, present:

```markdown
## Orchestrator Run Complete

**Project:** #<NUMBER>
**Feature branch:** <BRANCH>
**Exit code:** <0 or 1>

| Ticket | Title | Status |
|--------|-------|--------|
| #N     | ...   | OK/FAIL |

**Log:** /tmp/orchestrator-<PROJECT_NUMBER>.log
```

If all tickets passed:
- Check if the orchestrator already created a PR (it does when `--feature-branch` is set and all tickets pass).
- If not, suggest creating one.

If tickets failed:
- Show which failed and which are blocked.
- Offer options: re-run with `--max-parallel 1` for debugging, resume (already-done tickets will be skipped), or manual intervention.

---

## CLI reference (for constructing commands)

```
python -m scripts.orchestrator \
  --project N          # GitHub project number (required)
  --owner OWNER        # GitHub org (required)
  --repo OWNER/REPO    # GitHub repo (required)
  --feature-branch X   # Merge ticket branches into this branch
  --base-branch main   # PR target (default: main)
  --model sonnet       # Default agent model (default: sonnet)
  --max-parallel 3     # Concurrent agents (default: 1)
  --max-tickets 5      # Stop after N tickets (0 = all)
  --max-turns 50       # Claude turns per ticket (default: 50)
  --max-budget 5.0     # USD cap per ticket (default: 5.0)
  --max-retries 1      # Recovery attempts (default: 1)
  --on-failure stop     # stop or skip (default: stop)
  --branch-prefix ai   # Ticket branch prefix (default: ai)
  --config FILE        # Path to .orchestrator.yml
  --dry-run            # Preview only
  --verbose            # Debug logging
```

## Important rules

- **Do NOT reimplement orchestrator logic.** The Python package handles DAG resolution, branching, agent spawning, retries, merge conflicts, and PRs. Your job is to invoke it correctly and relay results.
- **Always dry-run first.** Let the user see the plan before committing to execution.
- **Clean tree required.** The orchestrator will refuse to run on a dirty working tree. Enforce this in pre-flight.
- **Logs are your friend.** The orchestrator writes detailed logs. Use them to diagnose issues rather than guessing.
- **Resume is safe.** Re-running the same command skips `status:done` tickets automatically. Tell the user this if they need to restart after a failure.
- **Horizontal migration tickets need a higher turn budget — bump, do not split.** If any ticket in the project migrates a shared contract (auth dependency, widely-used function signature, injected object) that ripples into many test files, default to `--max-turns 150` for the whole run. The default 50 is tuned for vertical work (concentrated in one area); horizontal migrations routinely burn 80–150 turns on mechanical test-fixture updates. Splitting such a ticket does not work — the test suite must be fully migrated to commit, so the whole fan-out has to land in one ticket.

## Diagnosing `out_of_turns` failures

If a ticket fails with reason `out_of_turns` (especially twice — once on first attempt, once on Recovery 1/1), the ticket is almost certainly a horizontal migration the project owner did not flag. Before retrying:

1. Confirm the pattern in the log: the agent was doing mechanical file-by-file edits (add `principal` to N mocks, add `--override` to N tests, etc.) rather than novel reasoning.
2. If yes, rerun the whole project with `--max-turns 150` (or `200` if the first retry also burned the full 80 budget). Done tickets skip; the failed ticket restarts with headroom.
3. If the recovery itself also got close to budget, the pragmatic move is the human finishes the ticket manually — 20 minutes of sed/find-and-replace beats a third agent attempt.

Bumping retries (`--max-retries 2`) is generally worse than bumping turns: each retry starts from a fresh branch and re-does discovery, so you spend turns on the same work twice.
