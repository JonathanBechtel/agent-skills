---
description: Turn one loose idea into a single well-formed GitHub issue, classified for whether an AI may run it unattended
argument-hint: "<description>" | #<N> [--repo REPO] [--autonomy auto|assisted|manual] [--runtime claude|codex|any] [--tier small|standard|deep] [--dry-run]
---

Run the `create-ticket` skill using `$ARGUMENTS`.

**Usage:**
- `/create-ticket "the CSV export only returns the current page"` — research the codebase, classify, show the verdict, then file.
- `/create-ticket #393` — re-form an existing stray issue into the standard shape and classify it in place.
- `/create-ticket "..." --dry-run` — print the ticket body and the verdict without creating anything.
- `/create-ticket "..." --autonomy assisted` — override the classification's outcome. The five axes still run; the skill still refuses `auto` if one fails, and says which.

This is for **one-off work** — a small bug, a quick idea, a minor improvement, the tail a review left behind. A spec that decomposes into many dependent tickets goes through `/create-project` instead.

One ticket per invocation. There is no bulk mode: classification is a judgment that wants a human looking at the verdict.
