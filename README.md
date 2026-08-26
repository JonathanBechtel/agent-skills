# agent-skills

The orchestrator skill chain, as one source shared by Claude Code and Codex CLI.

```
/create-product-pitch  →  tech spec  →  /create-qa-checklist  →  /create-project  →  /orchestrate  →  /ship
```

Each skill is one package directory. Both runtimes read that same directory
through a symlink, so there is no second copy to keep in step and bundled
metadata, scripts, references, and assets remain available.

## Why a repo

These files lived only at user level, in `~/.claude/skills` and `~/.codex/skills`,
as hand-maintained duplicates. They drifted — the Codex `ship` had lost the
simplification pass, and the Codex `orchestrate` had become a different procedure
entirely. An invariant maintained by hand, with no guard, is not an invariant.

Two things fix it structurally: a single package behind two directory symlinks, and
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
./install.sh     # symlinks into ~/.claude and ${CODEX_HOME:-$HOME/.codex}; backs up replacements
./validate.sh    # verify
```

Re-run `install.sh` after adding a skill. It is idempotent.

## Editing

Edit the package in `skills/`. Both runtimes see it immediately — no copying, no sync step.

The directory link is significant. Codex follows symlinked skill directories
while discovering `SKILL.md`, but its default walker ignores a `SKILL.md` that
is itself a symlink. Linking the whole package also makes `agents/openai.yaml`
and any bundled resources available automatically.

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

## Adding a skill

`./new-skill.sh <name> --global` or `./new-skill.sh <name> --repo` — the script
puts the file in the right place and wires both runtimes. The scope question is
the only judgment call:

> Does the skill name this repo's paths, commands, or conventions? Repo-scoped.
> Would it work unchanged in another checkout? Global.

**Global.** Created here in `skills/<name>/`. Run `./install.sh` to link it into
both runtimes, then commit and push — *that commit is the sync*. Nothing else
copies it anywhere.

The trap: writing a global skill while you happen to be standing in a repo, and
saving it into that repo's `.claude/skills`. It then works in one checkout and
nowhere else. If a skill is worth having everywhere, it belongs here.

**Repo-scoped.** Created in `<checkout>/.claude/skills/<name>/`, and committed to
*that* repo — never to this one. There is nothing to sync: `repos/<name>` is a
live link into the checkout, so it appears here the moment it exists.

The one thing to remember is the Codex entry point. Codex reads repo-scoped
skills from `.agents/skills`, not `.claude/skills`, so a skill in `.claude` alone
is invisible to it. `new-skill.sh` links the complete skill directory for you;
`validate.sh` reports missing entries and the old file-only symlink layout that
Codex does not discover.

Both scopes: run `./validate.sh` before committing.
