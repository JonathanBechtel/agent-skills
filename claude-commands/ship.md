---
description: Ship the current branch (or attach to a PR #) — commit, push, open PR, watch CI + bot reviewers, and optionally merge and watch the deploy
argument-hint: [PR#] [--merge] [--autonomous] [--rounds N] [--no-simplify]
---

Run the `ship` skill end-to-end using `$ARGUMENTS`.

**Usage:**
- `/ship` — no arg. The skill will (1) check the conversation for a recently-discussed PR number, (2) otherwise fall back to the PR for the current branch, (3) otherwise commit/push/open a new PR for the current branch. Always state which PR you picked in one line before mutating any state.
- `/ship <PR#>` — explicit PR. Skip Phase A and go straight to watching.
- `/ship --merge` — also land it: resolve review threads, squash-merge, watch the deploy.
- `/ship --autonomous` — unattended mode (implies `--merge`). Widens what may proceed without asking, per the skill's Autonomy contract. This is what `/orchestrate` uses.
- `/ship --rounds N` — override the size-derived review-round budget.

For unattended watching, prefer `/loop /ship` (or `/loop /ship <PR#>`). The skill self-paces via `ScheduleWakeup` at ~270s/tick.
