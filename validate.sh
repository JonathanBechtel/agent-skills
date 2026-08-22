#!/usr/bin/env bash
# Validate every skill against Codex's own frontmatter rules, and check that
# repo skills are actually reachable from Codex.
#
# This is the guard. Claude Code accepts frontmatter keys Codex rejects
# (when-to-use, argument-hint, user-invocable), and Codex additionally rejects
# angle brackets and bare "key: value" colons inside a description. One file
# serving both runtimes only stays valid if something checks.
#
# Global skills are enforced — they ship to both runtimes, so a failure is a
# failure. Repo skills are reported: whether they satisfy Codex's rules, and
# whether .agents/skills has an entry pointing at them. A skill can be perfectly
# valid and still invisible to Codex, because Codex reads repo-scoped skills
# from .agents/skills, not .claude/skills.
set -euo pipefail

REPO="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
VALIDATOR="$HOME/.codex/skills/.system/skill-creator/scripts/quick_validate.py"

if [ ! -f "$VALIDATOR" ]; then
  echo "Codex validator not found at $VALIDATOR" >&2
  echo "Install Codex CLI, or skip validation on this machine." >&2
  exit 2
fi

fail=0

echo "== global (enforced)"
for dir in "$REPO"/skills/*/; do
  printf '  %-22s ' "$(basename "$dir")"
  if python3 "$VALIDATOR" "$dir" >/dev/null 2>&1; then
    echo "ok"
  else
    echo "FAILED"
    python3 "$VALIDATOR" "$dir" 2>&1 | sed 's/^/      /'
    fail=1
  fi
done

if [ -d "$REPO/repos" ]; then
  echo
  echo "== repo skills (frontmatter / codex-reachable)"
  for repo in "$REPO"/repos/*/; do
    [ -e "$repo" ] || continue
    rname="$(basename "$repo")"
    root="$(dirname "$(dirname "$(realpath "$repo")")")"   # <checkout>/.claude/skills -> <checkout>
    echo "  $rname:"
    for skill in "$repo"*/; do
      [ -d "$skill" ] || continue
      sname="$(basename "$skill")"
      printf '    %-24s ' "$sname"

      if [ ! -f "${skill}SKILL.md" ]; then
        echo "no SKILL.md"
        continue
      fi

      if python3 "$VALIDATOR" "$skill" >/dev/null 2>&1; then
        printf 'valid'
      else
        printf 'claude-only'
      fi

      if [ -e "$root/.agents/skills/$sname/SKILL.md" ]; then
        echo " · codex-reachable"
      else
        echo " · NOT reachable from Codex (no .agents/skills/$sname)"
      fi
    done
    for flat in "$repo"*.md; do
      [ -e "$flat" ] || continue
      printf '    %-24s ' "$(basename "$flat")"
      echo "flat file — Codex cannot load this layout"
    done
  done
fi

exit "$fail"
