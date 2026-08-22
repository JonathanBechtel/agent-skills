# agent-skills

The orchestrator skill chain, as one source shared by Claude Code and Codex CLI.

```
/create-product-pitch  →  tech spec  →  /create-qa-checklist  →  /create-project  →  /orchestrate  →  /ship
```

Each skill is one file. Both runtimes read that same file through a symlink, so
there is no second copy to keep in step.

## Why a repo

These files lived only at user level, in `~/.claude/skills` and `~/.codex/skills`,
as hand-maintained duplicates. They drifted — the Codex `ship` had lost the
simplification pass, and the Codex `orchestrate` had become a different procedure
entirely. An invariant maintained by hand, with no guard, is not an invariant.

Two things fix it structurally: a single file behind two symlinks, and
`validate.sh`, which fails when a file stops being valid for either runtime.

## Layout

```
skills/<name>/SKILL.md          canonical body, read by both runtimes
skills/<name>/agents/openai.yaml Codex display metadata
claude-commands/<name>.md       thin Claude Code slash-command shims
install.sh                      create the symlinks (run once per machine)
validate.sh                     check every skill against Codex's own rules
```

## Install

```bash
./install.sh     # symlinks into ~/.claude and ~/.codex; backs up anything it replaces
./validate.sh    # verify
```

Re-run `install.sh` after adding a skill. It is idempotent.

## Editing

Edit the file in `skills/`. Both runtimes see it immediately — no copying, no sync step.

Then run `./validate.sh`. The frontmatter must satisfy **both** runtimes, and Codex
is the stricter one:

- only `name`, `description`, `license`, `allowed-tools`, `metadata` are allowed
  (Claude's `when-to-use`, `argument-hint`, and `user-invocable` are rejected)
- no angle brackets in `description`
- no bare `key: value` colon inside `description` — it breaks the YAML parse

Keep skills runtime-neutral. Where a capability differs, name both primitives in a
**Runtime adapters** table rather than writing for one runtime: Claude Code has
`Agent`, `ScheduleWakeup`, and `TaskCreate`; Codex CLI has `spawn_agent` + `wait`
(needs `multi_agent = true`) and an inline `sleep`. Skills are `/name` in Claude
Code and `$name` in Codex.

## Other machines

Clone and run `./install.sh`. That is the whole setup — the sprite and the laptop
then run identical skills.

## Repo-specific skills

Some skills belong to one repo and are committed to it. Those files stay where
they are — tracked, and working in worktrees, CI, and on the sprite, none of
which a machine-specific symlink survives.

`install.sh` instead links the other way: `repos/<name>` points into that
checkout's `.claude/skills`, so everything is reachable from here without moving
anything. Edit through the link and you are editing the repo's own file.

```
repos/draft-app       -> ~/draft-app/.claude/skills
repos/platform-ai     -> ~/platform-ai/.claude/skills
```

Configure which checkouts in `repos.conf`. `repos/` itself is gitignored — the
config is portable, the links are per-machine. Missing checkouts are skipped.

`validate.sh` reports on repo skills without enforcing: most are Claude-only by
design, so whether they satisfy Codex's stricter rules is information, not a
verdict. It also flags the flat `<name>.md` layout, which Codex cannot load at
all — that is what to convert if a repo skill should work in both runtimes.

## Deprecated

`deprecated/` holds retired skills, kept for reference and out of the live
directories. A dead skill is not harmless: its description still competes for
selection when a runtime picks a skill for a task.
