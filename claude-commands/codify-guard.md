---
description: Turn a regression that already happened into a permanent, deterministic guard in lint, pre-commit, and CI
argument-hint: "<what went wrong>" | #<N> [--dry-run]
---

Run the `codify-guard` skill using `$ARGUMENTS`.

**Usage:**
- `/codify-guard "the admin page said activation was inert after we wired it up"` — work out the class, decide whether it is mechanizable, write the checker plus its proof-of-catch, and register it everywhere the repo expects.
- `/codify-guard #1121` — take the incident from an existing issue.
- `/codify-guard "..." --dry-run` — report the class, the mechanizability verdict, and the proposed shape without writing anything.

**Invoke it half-formed.** "Something about templates claiming things the code doesn't do" is enough input. Deciding whether a rule is even possible is the skill's job, not yours.

The skill will **refuse** two things, and both refusals are the point:

- **No incident, no guard.** If you cannot name what actually broke — an issue, a commit, a finding, something that just bit you — it stops. Speculative guards cost CI time forever and catch nothing.
- **Not everything is mechanizable.** If the class needs human judgment, it says so rather than shipping a weak regex that passes vacuously. A guard that cannot fail is worse than none, because it advertises protection that is not there.

One incident, one class, one guard per invocation.
